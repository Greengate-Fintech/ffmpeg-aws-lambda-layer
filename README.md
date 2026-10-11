# FFmpeg/FFprobe for AWS Lambda

A Lambda layer containing a static version of FFmpeg/FFprobe utilities from the [`FFmpeg`](https://www.ffmpeg.org/) Linux package, built for Amazon Linux 2023 based Lambda runtimes (`nodejs24.x`, `nodejs22.x`, `python3.13`) on both `x86_64` and `arm64`. The binaries need glibc 2.28 or later, so they do not run on Amazon Linux 2 runtimes.

> This README covers general usage, building, and manual deployment. [`README-SAR.md`](README-SAR.md) is a
> shorter, separate description rendered by the AWS Serverless Application Repository console itself (see
> `template.yaml`'s `ReadmeUrl`) — the two are written for different audiences and are not duplicates.
> For AI agents working on this codebase, see [`CLAUDE.md`](CLAUDE.md) and [`docs/architecture.md`](docs/architecture.md).

## Usage

Absolutely the easiest way of using this is to pull it directly from the AWS Serverless Application repository into a CloudFormation/SAM application, or deploy directly from the Serverless Application Repository into your account, and then link as a layer. 

The `ffmpeg` and `ffprobe` binaries will be in `/opt/bin/` after linking the layer to a Lambda function.

For more information, check out the [ffmpeg-lambda-layer](https://serverlessrepo.aws.amazon.com/applications/arn:aws:serverlessrepo:us-east-1:145266761615:applications~ffmpeg-lambda-layer) application in the Serverless App Repository.

For manual deployments and custom builds, read below...

## Prerequisites

* Unix Make environment
* AWS command line utilities (just for deployment)

## Deploying to AWS as a layer

This package bundles a pinned FFmpeg 8.1 release-branch build (GPL variant, with libx264 and libvpx) from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), one build per architecture. The exact dated release, asset names and SHA-256 hashes are in [`versions.mk`](versions.mk). The `Makefile` verifies the SHA-256 of each download before it extracts anything, and no URL in this repository points at a "latest" alias.

FFmpeg 7.1 and later keep every input frame when converting variable-frame-rate input (such as a browser-recorded WebM) to MP4 without a frame-rate option. Earlier versions, including 7.0.2 from the previous build source, duplicate frames in that case. `scripts/check-layer.sh` tests exactly that.

The output is under `build/<arch>/` (`layer/bin/` for the extracted binaries, `output.yaml` for the packaged CloudFormation template).

```
make build ARCH=x86_64               # download, verify and extract (ARCH is x86_64 or arm64; default x86_64)
make check ARCH=x86_64               # build, then run the functional check against the binaries
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
2. Read that release's `checksums.sha256` and copy the `linux64-gpl` and `linuxarm64-gpl` asset names and hashes into `versions.mk`.
3. Run `make check ARCH=x86_64` and `make check ARCH=arm64` from a clean `build/`, then publish both layers.

### example usage

An example project is in the [example](example) directory. It sets up two buckets, and listens to file uploads on the first bucket to convert and generate thumbnails from uploaded video files. You can deploy it from the root Makefile using:

```
make deploy-example DEPLOYMENT_BUCKET=<YOUR BUCKET NAME>
```

For more information on using FFmpeg and FFprobe, check out <https://ffmpeg.org/documentation.html>

## Author

Gojko Adzic <https://gojko.net>

## License

* These scripts: [MIT](https://opensource.org/licenses/MIT)
* FFmpeg: GPLv2.1 <http://ffmpeg.org/legal.html>, the BtbN GPL build is GPLv3 <https://github.com/BtbN/FFmpeg-Builds>

## LGPL version

*  [Giuseppe Battista](http://github.com/giusedroid) created a build that contains only LGPL components, for organisations that are concerned about GPL licensing. See it at <https://github.com/giusedroid/ffmpeg-aws-lambda-layer/tree/license/lgpl>
