# Pinned FFmpeg builds. Each architecture names one BtbN/FFmpeg-Builds dated
# autobuild release asset (FFmpeg release branch 8.1, GPL variant, static) and
# its SHA-256. Never point these at a "latest" URL. To bump, see CLAUDE.md.
BTBN_RELEASE := autobuild-2026-10-10-13-04
FFMPEG_VERSION := n8.1.3-17-gc389840894

FFMPEG_ASSET_x86_64 := ffmpeg-$(FFMPEG_VERSION)-linux64-gpl-8.1.tar.xz
FFMPEG_SHA256_x86_64 := fc332aa9e6d204ea674432c9e2c53696f75ff6d7d11de337b286bde494d7c583

FFMPEG_ASSET_arm64 := ffmpeg-$(FFMPEG_VERSION)-linuxarm64-gpl-8.1.tar.xz
FFMPEG_SHA256_arm64 := 3cfb2ce6c6a9c53ce0879c108d47425ed7142f383338284b03c05eef0c7baa56
