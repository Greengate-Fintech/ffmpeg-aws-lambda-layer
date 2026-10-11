#!/usr/bin/env bash
# Checks a built layer directory the way Lambda will load it (binaries in bin/,
# shared libraries in lib/ on LD_LIBRARY_PATH):
#   1. the layer has no symlinks, and unzipped it fits well inside Lambda's 262,144,000-byte limit for
#      a function plus all its layers;
#   2. every shared library ffmpeg and ffprobe need resolves;
#   3. the ffmpeg under test does not duplicate frames when it converts a
#      browser-style WebM to MP4 without a frame-rate flag.
#
# Usage: scripts/check-layer.sh [layer-dir]
#   layer-dir      directory holding bin/ffmpeg, bin/ffprobe and lib/
#                  (default build/x86_64/layer)
# Environment:
#   RUNNER         command prefix for running the binaries under test, for example
#                  an emulator wrapper for arm64 (default: none)
#   FIXTURE_FFMPEG / FIXTURE_FFPROBE  tools used only to generate and count the input WebM
#                  (default: ffmpeg and ffprobe on PATH)
set -euo pipefail

layer_dir=$(cd "${1:-build/x86_64/layer}" && pwd)
fixture_ffmpeg=${FIXTURE_FFMPEG:-ffmpeg}

# aws cloudformation package zips the layer following symlinks, so each link
# would become another full copy of its library and the size below would
# understate the published layer.
links=$(find "$layer_dir" -type l)
if [ -n "$links" ]; then
  echo "FAIL: layer contains symlinks, which packaging would copy as full files:" >&2
  echo "$links" >&2
  exit 5
fi

# Leaves about 22 MB of the 262,144,000-byte limit for the function code.
max_bytes=240000000
layer_bytes=$(du -sb "$layer_dir" | cut -f1)
echo "layer size: $layer_bytes bytes (limit $max_bytes)"
if [ "$layer_bytes" -gt "$max_bytes" ]; then
  echo "FAIL: layer is $layer_bytes bytes unzipped, over the $max_bytes-byte budget" >&2
  exit 3
fi

# shellcheck disable=SC2206
runner=(${RUNNER:-} env "LD_LIBRARY_PATH=$layer_dir/lib")
ffmpeg=("${runner[@]}" "$layer_dir/bin/ffmpeg")
ffprobe=("${runner[@]}" "$layer_dir/bin/ffprobe")

for bin in ffmpeg ffprobe; do
  deps=$("${runner[@]}" ldd "$layer_dir/bin/$bin")
  if grep -q "not found" <<<"$deps"; then
    echo "FAIL: $bin has unresolved shared libraries:" >&2
    grep "not found" <<<"$deps" >&2
    exit 4
  fi
done
echo "shared libraries: all resolve"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 300 frames at a 1 ms time base. Within every five frames the timestamps (ms)
# are offset by 0, 8, 68, 83, 133 and the pattern repeats every 173 ms, so
# ffmpeg guesses a 1000 fps rate, as it does for browser recordings.
expected_frames=300
pts="(floor(N/5)*173 + if(eq(mod(N,5),1),8,if(eq(mod(N,5),2),68,if(eq(mod(N,5),3),83,if(eq(mod(N,5),4),133,0)))))/1000/TB"
"$fixture_ffmpeg" -loglevel error -y -f lavfi -i "testsrc2=size=320x240:rate=1000:duration=0.3" \
  -vf "setpts='$pts'" -fps_mode passthrough -c:v libvpx -b:v 300k -f webm "$work/in.webm"

# The fixture is what the test is built on, so confirm it has the frames we expect.
in_frames=$("${FIXTURE_FFPROBE:-ffprobe}" -v error -select_streams v:0 -count_frames \
  -show_entries stream=nb_read_frames -of csv=p=0 "$work/in.webm")
if [ "$in_frames" -ne "$expected_frames" ]; then
  echo "FAIL: fixture has $in_frames frames, expected $expected_frames" >&2
  exit 2
fi

# Plain -f mp4, deliberately without a frame-rate option.
"${ffmpeg[@]}" -loglevel error -y -i "$work/in.webm" -f mp4 "$work/out.mp4"

out_frames=$("${ffprobe[@]}" -v error -select_streams v:0 -count_frames \
  -show_entries stream=nb_read_frames -of csv=p=0 "$work/out.mp4")

min=$(( expected_frames * 95 / 100 ))
echo "input frames: $expected_frames, output frames: $out_frames (allowed $min-$expected_frames)"
if [ "$out_frames" -lt "$min" ] || [ "$out_frames" -gt "$expected_frames" ]; then
  echo "FAIL: output frame count outside 95-100% of input" >&2
  exit 1
fi
"${ffmpeg[@]}" -version | head -1
echo "PASS"
