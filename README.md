# FFmpeg/FFprobe for AWS Lambda

A Lambda layer containing FFmpeg/FFprobe from the [`FFmpeg`](https://www.ffmpeg.org/) project, built for Amazon Linux 2023 based Lambda runtimes (`nodejs24.x`, `nodejs22.x`, `python3.13`) on both `x86_64` and `arm64`. It is a shared build: the `ffmpeg` and `ffprobe` binaries load the FFmpeg libraries (`libavcodec` and the rest) from the layer's `lib/`, and link dynamically against glibc 2.28 or later, so they do not run on Amazon Linux 2 runtimes.

> This README covers general usage, building, and manual deployment. [`README-SAR.md`](README-SAR.md) is a
> shorter, separate description rendered by the AWS Serverless Application Repository console itself (see
> `template.yaml`'s `ReadmeUrl`) — the two are written for different audiences and are not duplicates.
> For AI agents working on this codebase, see [`CLAUDE.md`](CLAUDE.md) and [`docs/architecture.md`](docs/architecture.md).

## Usage

Absolutely the easiest way of using this is to pull it directly from the AWS Serverless Application repository into a CloudFormation/SAM application, or deploy directly from the Serverless Application Repository into your account, and then link as a layer. 

The `ffmpeg` and `ffprobe` binaries will be in `/opt/bin/` after linking the layer to a Lambda function, and the FFmpeg shared libraries in `/opt/lib/` (on Lambda's `LD_LIBRARY_PATH`).

For more information, check out the [ffmpeg-lambda-layer](https://serverlessrepo.aws.amazon.com/applications/arn:aws:serverlessrepo:us-east-1:145266761615:applications~ffmpeg-lambda-layer) application in the Serverless App Repository.

For manual deployments and custom builds, read below...

## Prerequisites

* Unix Make environment
* `ffmpeg` and `ffprobe` on the host `PATH`, with the `libvpx` encoder (just for `make check`, which uses them to generate and count its test WebM; override with `FIXTURE_FFMPEG`/`FIXTURE_FFPROBE`)
* Docker with arm64 emulation for `make check ARCH=arm64` on an x86_64 host (see below)
* AWS command line utilities (just for deployment)

## Deploying to AWS as a layer

This package bundles a pinned FFmpeg 8.1 release-branch build (GPL variant, shared libraries, with libx264 and libvpx) from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), one build per architecture. The exact dated release, asset names and SHA-256 hashes are in [`versions.mk`](versions.mk). The `Makefile` checks each download against the pinned SHA-256 before it extracts anything (this detects any change to the asset after pinning; the pinned hashes were cross-checked against BtbN's published `checksums.sha256` at pin time, which does not prove BtbN's own build is trustworthy), and no URL in this repository points at a "latest" alias.

FFmpeg 7.1 and later keep every input frame when converting variable-frame-rate input (such as a browser-recorded WebM) to MP4 without a frame-rate option. Earlier versions, including 7.0.2 from the previous build source, duplicate frames in that case. Evidence: releases 4.4.1, 6.1.1 and 7.0.2 were tested and duplicate frames when converting variable-frame-rate WebM (1 ms time base, no declared frame rate) to MP4 without a frame-rate option, while 7.1, 7.1.1, 8.0 and 8.0.1 keep the input frames; the change matches the upstream FFmpeg commit "lavf/movenc: mark mov/mp4 as supporting VFR". This repo's `make check` confirmed 7.0.2 failing (10390 frames from 300) and 8.1.3 passing (300). `scripts/check-layer.sh` tests exactly that.

The output is under `build/<arch>/` (`layer/bin/` for the binaries, `layer/lib/` for the FFmpeg shared libraries, `output.yaml` for the packaged CloudFormation template). The static builds are not used because each of `ffmpeg` and `ffprobe` carries its own copy of the libraries: the x86_64 pair is 344 MB unzipped, over Lambda's 262,144,000-byte limit for a function and all its layers. The shared build is about 213 MB (x86_64) and 164 MB (arm64). Only the libraries' soname files are kept, as regular files, because `aws cloudformation package` zips each symlink as another full copy.

```
make build ARCH=x86_64               # download, verify and extract (ARCH is x86_64 or arm64; default x86_64)
make check ARCH=x86_64               # build, then check the layer (size, no symlinks, libraries resolve, frame count)
                                     # and the per-architecture template's local paths (make check-template)
make deploy ARCH=x86_64 DEPLOYMENT_BUCKET=<YOUR BUCKET NAME>
make deploy ARCH=arm64 DEPLOYMENT_BUCKET=<YOUR BUCKET NAME>
```

On an x86_64 host, `make check ARCH=arm64` runs the arm64 binaries in an `amazonlinux:2023` container under QEMU. That needs Docker with arm64 emulation (`docker run --privileged --rm tonistiigi/binfmt --install arm64`). Set `DOCKER="sudo docker"` if Docker needs `sudo`.

### configuring the deployment

| `ARCH` | Stack name | Layer name |
|---|---|---|
| `x86_64` (default) | `ffmpeg-lambda-layer` | `ffmpeg` |
| `arm64` | `ffmpeg-arm64-lambda-layer` | `ffmpeg-arm64` |

Provide `STACK_NAME` or `LAYER_NAME` when calling `make deploy` to use alternative names. `LayerName` and `Architecture` are passed to `template.yaml` as parameter overrides.

### bumping FFmpeg

1. Pick a BtbN `autobuild-YYYY-MM-DD-HH-MM` release whose assets are on a release branch (`n8.x`, suffix `-8.x`), never `master`.
2. Read that release's `checksums.sha256` and copy the `linux64-gpl-shared` and `linuxarm64-gpl-shared` asset names and hashes into `versions.mk`.
3. Run `make check ARCH=x86_64` and `make check ARCH=arm64` (binaries rebuild whenever `versions.mk` changes), then publish both layers.

### example usage

An example project is in the [example](example) directory. It sets up two buckets, and listens to file uploads on the first bucket to convert and generate thumbnails from uploaded video files. You can deploy it from the root Makefile using:

```
make deploy-example DEPLOYMENT_BUCKET=<YOUR BUCKET NAME>
```

For more information on using FFmpeg and FFprobe, check out <https://ffmpeg.org/documentation.html>

## Author

Gojko Adzic <https://gojko.net>

## License

This is a public fork of [serverlesspub/ffmpeg-aws-lambda-layer](https://github.com/serverlesspub/ffmpeg-aws-lambda-layer): every change committed here is published openly. See [LICENSE.txt](LICENSE.txt) for the full terms and disclaimer.

* These scripts, templates and docs: [MIT](https://opensource.org/licenses/MIT) (original work by the upstream contributors; modifications Copyright (c) 2026 the contributors to this fork).
* FFmpeg: LGPL 2.1 or later with optional GPL components <https://ffmpeg.org/legal.html>. The binaries are not in this repository; the BtbN `gpl` build that `make build` downloads is configured with `--enable-gpl --enable-version3`, so a built layer is **GPL version 3 or later**. Whoever distributes a built layer (for example via the Serverless Application Repository, or by sharing it with another account) must meet the GPL's terms, including making the corresponding source available.
* Provided "as is", without warranty. Not legal advice.

## LGPL version

*  [Giuseppe Battista](http://github.com/giusedroid) created a build that contains only LGPL components, for organisations that are concerned about GPL licensing. See it at <https://github.com/giusedroid/ffmpeg-aws-lambda-layer/tree/license/lgpl>
