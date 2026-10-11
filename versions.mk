# Pinned FFmpeg builds. Each architecture names one BtbN/FFmpeg-Builds dated
# autobuild release asset (FFmpeg release branch 8.1, GPL variant, shared
# libraries, linked against glibc >= 2.28) and its SHA-256. Never point these
# at a "latest" URL. To bump, see CLAUDE.md.
BTBN_RELEASE := autobuild-2026-10-10-13-04
FFMPEG_VERSION := n8.1.3-17-gc389840894

FFMPEG_ASSET_x86_64 := ffmpeg-$(FFMPEG_VERSION)-linux64-gpl-shared-8.1.tar.xz
FFMPEG_SHA256_x86_64 := 8281a68e82acc48d8bf6c1fc3276d8ad42a36a219f958d903774ebf5f95334a8

FFMPEG_ASSET_arm64 := ffmpeg-$(FFMPEG_VERSION)-linuxarm64-gpl-shared-8.1.tar.xz
FFMPEG_SHA256_arm64 := f3a00fefa352d4d70518fbe1db3df82980ba916c9eb645c96b3e1a84488571d1
