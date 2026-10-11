# FFmpeg/FFprobe Lambda Layer for Amazon Linux 2023

Pinned shared-library build of FFmpeg/FFprobe (linked against glibc 2.28 or later), packaged as a Lambda layer for `x86_64` or `arm64`. The bundled FFmpeg version is pinned in `versions.mk` (currently the 8.1 release branch).

This application provides a single output, `LayerVersion`, which points to a
Lambda Layer ARN you can use with Lambda runtimes based on Amazon Linux 2023 (such
as `nodejs24.x`, `nodejs22.x` and `python3.13`). The binaries are at `/opt/bin/ffmpeg` and `/opt/bin/ffprobe`, and the FFmpeg libraries they load are in `/opt/lib`.

For an example of how to use the layer, check out 
<https://github.com/serverlesspub/ffmpeg-aws-lambda-layer/tree/master/example>
