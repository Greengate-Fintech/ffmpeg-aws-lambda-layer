#!/usr/bin/env bash
# Functional check for a built layer: the ffmpeg under test must not duplicate
# frames when it converts a browser-style WebM to MP4 without a frame-rate flag.
#
# Usage: scripts/check-layer.sh [layer-bin-dir]
#   layer-bin-dir  directory holding ffmpeg and ffprobe (default build/x86_64/layer/bin)
# Environment:
#   RUNNER         command prefix for running the binaries under test, for example
#                  an emulator wrapper for arm64 (default: none)
#   FIXTURE_FFMPEG / FIXTURE_FFPROBE  tools used only to generate and count the input WebM
#                  (default: ffmpeg and ffprobe on PATH)
set -euo pipefail

bin_dir=$(cd "${1:-build/x86_64/layer/bin}" && pwd)
fixture_ffmpeg=${FIXTURE_FFMPEG:-ffmpeg}
# shellcheck disable=SC2206
runner=(${RUNNER:-})
ffmpeg=("${runner[@]}" "$bin_dir/ffmpeg")
ffprobe=("${runner[@]}" "$bin_dir/ffprobe")

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
