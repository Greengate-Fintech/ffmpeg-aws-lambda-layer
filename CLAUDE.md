# Instructions for AI agents working on this codebase

## Project Overview

`ffmpeg-aws-lambda-layer` packages a shared-library build of **FFmpeg**/**FFprobe** (glibc-linked, needs glibc 2.28 or later; from
[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), pinned in `versions.mk`) as an **AWS Lambda layer**, using
AWS SAM (`AWS::Serverless-2016-10-31`). It is a **build/publish artefact repository**, not a running
service: there is no handler code here that executes on every invocation of some Lambda — the only
"product" is the layer's `.zip` content (`ffmpeg`/`ffprobe` binaries under `bin/`, the FFmpeg shared libraries under `lib/`) and the
CloudFormation/SAM template that wraps it.

Per the org repository inventory (`verifime-adr/doc/other/github-repo-inventory.md`, abbreviation `FLL`,
topic `infrastructure-tooling`): "Pre-compiled FFmpeg/FFprobe binaries packaged as an AWS Lambda layer for
video/media processing in serverless functions."

**Origin**: this repository is a fork of [`serverlesspub/ffmpeg-aws-lambda-layer`](https://github.com/serverlesspub/ffmpeg-aws-lambda-layer)
(Gojko Adzic), now hosted under `Greengate-Fintech`. Several artefacts still carry the upstream identity
verbatim — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question) below before assuming
any URL, ARN, or author byline in this repo is Greengate-Fintech's own.

There is no CI/CD in this repository — no `.github/workflows/`, only a `Makefile`. Building and publishing
the layer is a manual, local operation using the AWS CLI (see [Build & Publish](#build--publish)).

## What This Repo Is Not

- **Not a Lambda function repo.** There is no `RequestHandler`, no `exports.handler` at the top level of
  this repo (the `example/` directory's `index.js` handler is sample/reference code only, deployed by a
  *separate* example stack — see [The `example/` directory](#the-example-directory) below).
- **Not message-driven.** There is no SQS/SNS/EventBridge trigger, no retry/DLQ semantics, and therefore no
  `docs/failure-scenarios.md` in this repo (see the note in `docs/architecture.md` for why that document
  doesn't exist here, and what "failure" means for a build/publish artefact instead).
- **Not infrastructure for a running service.** `additional-integration-cdk`'s convention of "app code here,
  infra in the CDK repo" doesn't apply — the SAM template *is* the artefact's packaging, and CDK stacks in
  *consumer* repositories reference the resulting layer by ARN (see [Ecosystem Position](#ecosystem-position)).

## Architecture Summary

| Aspect | Detail |
|---|---|
| Packaging | AWS SAM (`template.yaml`), one resource: `AWS::Serverless::LayerVersion` |
| Binary source | A dated BtbN/FFmpeg-Builds autobuild release (`autobuild-YYYY-MM-DD-HH-MM`), GPL variant, release branch 8.1, one asset per architecture. The release tag, asset names and SHA-256 hashes are in `versions.mk`; the `Makefile` verifies the hash before extracting. No `latest` URL is used anywhere |
| FFmpeg version bundled | Set by `versions.mk` (`n8.1.3-17-gc389840894` at the time of writing, the same for x86_64 and arm64). Confirm with `build/<arch>/layer/bin/ffmpeg -version`. FFmpeg 7.1+ is required: earlier versions duplicate frames when converting browser-recorded WebM to MP4 without a frame-rate option. Evidence: Regula-Face-API-Deployment [issue #36](https://github.com/Greengate-Fintech/Regula-Face-API-Deployment/issues/36) (third comment): its version test shows 4.4.1, 6.1.1 and 7.0.2 duplicating frames, and 7.1, 7.1.1, 8.0 and 8.0.1 keeping the input frames. This repo's `make check` confirmed 7.0.2 failing (10390 frames from 300) and 8.1.3 passing (300). |
| Architectures | `x86_64` (stack `ffmpeg-lambda-layer`, layer `ffmpeg`) and `arm64` (stack `ffmpeg-arm64-lambda-layer`, layer `ffmpeg-arm64`), chosen with `make ... ARCH=` |
| Compatible runtimes | `nodejs24.x`, `nodejs22.x`, `python3.13` (`template.yaml`'s `CompatibleRuntimes`). The binaries are dynamically linked against glibc (needs 2.28 or later), so they suit Amazon Linux 2023 runtimes and not Amazon Linux 2 |
| Distribution | AWS Serverless Application Repository (SAR), application `ffmpeg-lambda-layer` — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question) |
| Licence | Layer packaging (this repo's scripts): MIT. FFmpeg itself: GPLv2.1; the BtbN GPL build: GPLv3 (see `LICENSE.txt`, `README.md`) |
| Output location | `AWS::Serverless::LayerVersion` from `build/<arch>/layer` (the Makefile fetches and verifies binaries there before `cloudformation package` runs) |

Full build/publish/consume flow, including a diagram: [docs/architecture.md](docs/architecture.md).

## Build & Publish

```bash
make build ARCH=x86_64                               # download, verify SHA-256 and extract (ARCH: x86_64 | arm64)
make check ARCH=x86_64                               # build, then run scripts/check-layer.sh against the layer
make deploy ARCH=x86_64 DEPLOYMENT_BUCKET=<your-s3-bucket>   # build + package + deploy the layer stack
make deploy-example DEPLOYMENT_BUCKET=<your-s3-bucket>   # build + deploy the example consumer stack
make clean                                            # remove build/ (forces a re-fetch of the FFmpeg tarball)
```

`make check` is the only test. It fails if the layer directory is over 240,000,000 bytes (`du -sb`; Lambda's
limit for a function and all its layers is 262,144,000), if it contains any symlink (`aws cloudformation
package` zips each link as a full copy), or if `ldd` reports a library of `ffmpeg`/`ffprobe` as not found,
running the binaries with `LD_LIBRARY_PATH=<layer>/lib` as Lambda will. It then generates a WebM with irregular timestamps (a 1 ms time base, as browsers
record), converts it with a plain `-f mp4` and requires the output to hold 95-100% of the input frames.
FFmpeg 7.0.2 (the previous build source) fails it with about 10,000 frames from 300. For `ARCH=arm64` on
an x86_64 host the binaries run in an `amazonlinux:2023` container under QEMU (see `README.md`).

Key `Makefile` targets, in dependency order:
1. `build/<arch>/layer/bin/ffmpeg` — downloads the asset named in `versions.mk` for `$(ARCH)`, stops if its
   SHA-256 differs (`FFMPEG_SHA256_OVERRIDE` can be set to test that), then extracts `ffmpeg`/`ffprobe` into
   `build/<arch>/layer/bin/` and each FFmpeg shared library, once, as a regular file named by its soname
   (`libavcodec.so.62` and so on) into `build/<arch>/layer/lib/`. Headers, pkg-config files, docs and
   `ffplay` are left out. The static assets are not used: their x86_64 `ffmpeg` plus `ffprobe` is 344 MB,
   over Lambda's size limit.
2. `build/<arch>/output.yaml` — `aws cloudformation package` uploads `build/<arch>/layer` to
   `$(DEPLOYMENT_BUCKET)` and rewrites the `ContentUri` of a per-architecture copy of `template.yaml`.
   `README-SAR.md` and `LICENSE.txt` are copied into `build/<arch>/` beside it, because package resolves
   `ReadmeUrl` and `LicenseUrl` relative to the template. `make check-template` (part of `make check`,
   `scripts/check-template-paths.sh`) fails if `ContentUri`, `ReadmeUrl` or `LicenseUrl` names a local
   path that does not exist relative to the per-architecture template.
3. `deploy` — `aws cloudformation deploy` of the packaged template with `LayerName` and `Architecture`
   parameter overrides, stack name `$(STACK_NAME)` (`ffmpeg-lambda-layer` for x86_64,
   `ffmpeg-arm64-lambda-layer` for arm64), then prints the stack's `Outputs` (the layer's `LayerVersion` ARN).

### Bumping FFmpeg

Edit `versions.mk` only: choose a newer BtbN `autobuild-*` release on a release branch (`n8.x`, never
`master`), copy the `linux64-gpl-shared` and `linuxarm64-gpl-shared` asset names and hashes from that release's
`checksums.sha256`, run `make check` for both architectures (the binaries rebuild whenever `versions.mk` changes), then publish both layers.
Publishing creates a new layer version, so the consumer's ARN must be bumped separately.

Publishing a new **SAR** application version (as opposed to a plain private CloudFormation stack deploy) is
a separate, manual step not scripted anywhere in this repo — see the open question below.

## Upstream vs. fork identity (open question)

This repository is a fork of `serverlesspub/ffmpeg-aws-lambda-layer`. Several places in the repo still
reference the **upstream** project's identity, and it is not confirmed whether Greengate-Fintech has ever
re-published this fork as its own SAR application, or whether internal consumers still (knowingly or not)
consume the original third-party SAR listing:

- `template.yaml`'s `Metadata.AWS::ServerlessRepo::Application` block: `Author: Gojko Adzic`,
  `HomePageUrl`/`SourceCodeUrl: https://github.com/serverlesspub/ffmpeg-aws-lambda-layer`,
  `SemanticVersion: 1.0.0`.
- `README.md` links to
  `https://serverlessrepo.aws.amazon.com/applications/arn:aws:serverlessrepo:us-east-1:145266761615:applications~ffmpeg-lambda-layer`
  — SAR account `145266761615` is the **original publisher's** AWS account, not a Greengate-Fintech account
  (Greengate-Fintech's known non-prod/prod accounts are `921483706620`/`772479554838` — see
  [Ecosystem Position](#ecosystem-position)).
- `example/template-sar.yaml` deploys the example by referencing that same third-party SAR application ARN
  directly (`ApplicationId: arn:aws:serverlessrepo:us-east-1:145266761615:applications/ffmpeg-lambda-layer`).

> **TODO(owner):** Confirm whether Greengate-Fintech has published its own SAR application/private
> CloudFormation stack from this fork (and if so, under which account/ARN and at which `SemanticVersion`),
> or whether the layer consumed internally (see `Regula-Face-API-Deployment` below) was deployed by manually
> running `make deploy` once against a Greengate-Fintech account rather than via SAR at all. The confirmed
> consumer's layer ARN (`arn:aws:lambda:ap-southeast-2:<account>:layer:ffmpeg:1`, a plain Lambda layer ARN,
> not a SAR application ARN) is consistent with the latter — a one-off `make deploy`/manual publish — but
> this has not been verified against deployment history or account resources.

## The `example/` directory

`example/` is a **separate, self-contained SAM application** demonstrating how a consumer Lambda uses the
layer — it is not part of the layer's own build. It has its own `Makefile`, `template.yaml` (references the
layer stack's `Outputs.LayerVersion` by CloudFormation cross-stack lookup via `aws cloudformation
describe-stacks`, see `example/Makefile`'s `LAMBDA_LAYER` variable) and `template-sar.yaml` (references the
upstream SAR application ARN directly instead, see above).

`example/src/index.js` is a Node.js 10.x S3-triggered handler that downloads an uploaded video, shells out to
`/opt/bin/ffmpeg` (the path every Lambda layer's content is mounted at) to extract a thumbnail frame, and
uploads the result to a second bucket. This is the same `/opt/bin/ffmpeg` invocation pattern used by the
confirmed real consumer, `Regula-Face-API-Deployment` — see below.

## Ecosystem Position

This is a leaf/infrastructure-tooling repository: nothing in this repo depends on any other Greengate-Fintech
repo, but at least one other repo depends on **its output** (a deployed Lambda layer), not on this repo's
source directly (there is no package/module import relationship — only "some AWS account has a
`layer:ffmpeg` Lambda layer version deployed").

**Confirmed consumer**: [`Regula-Face-API-Deployment`](https://github.com/Greengate-Fintech/Regula-Face-API-Deployment)
(CDK infrastructure for the Regula biometric face verification service):

- `lib/constants.ts:88` (dev) and `:109` (prod) hard-code the layer ARN by convention rather than importing
  it from this repo or from a CloudFormation export:
  ```
  ffmpegLayerArn: `arn:aws:lambda:${region}:${account}:layer:ffmpeg:1`
  ```
  resolving to `arn:aws:lambda:ap-southeast-2:921483706620:layer:ffmpeg:1` (non-prod) and
  `arn:aws:lambda:ap-southeast-2:772479554838:layer:ffmpeg:1` (prod) — i.e. **layer version `1`, pinned**, in
  each of Regula's own accounts. This is a plain Lambda layer ARN, not a reference to the SAR application
  itself (see the open question above).
- `lib/regula-face-api-s3-bucket-stack.ts:121-125` imports that ARN via
  `lambda.LayerVersion.fromLayerVersionArn(...)` and attaches it (`layers: [ffmpegLayer]`) to the
  `ConvertFileFunction` Lambda (`regula-face-api-s3-bucket-stack.ts:138`), which is triggered by an S3
  `OBJECT_CREATED` event on a `video.mp4` upload.
- `lambda/regula-face-api-s3-video-convert-function/convert-video-function.ts:57-61` shells out to
  `/opt/bin/ffmpeg` (the path this layer's content is mounted at inside any Lambda that attaches it) to
  transcode the uploaded session video to MP4, exactly mirroring `example/src/index.js`'s invocation
  pattern in this repo.

No other repository under `/home/user/` (searched exhaustively for `ffmpeg`, `ffprobe`, `FFMPEG_LAYER`, and
`serverlessrepo`, case-insensitive) references this layer, an FFmpeg binary, or the upstream SAR
application. The pinned FFmpeg 8.x build in this repo is published as `layer:ffmpeg:2` (x86_64) and `layer:ffmpeg-arm64:1`
(arm64) in each account (the publish is done by a person, not by an agent). `Regula-Face-API-Deployment` is
then changed to attach those ARNs. Until that happens, it still uses the old `:1`.
Because `Regula-Face-API-Deployment` pins layer **version 1** by ARN, a new layer version
published from this repo does **not** automatically propagate to that consumer — it would need its own CDK
change to bump the `:1` suffix. Keep this in mind before assuming "publish a new version here" is
sufficient to ship an FFmpeg update anywhere else in the org.

> **TODO(owner):** Confirm with the Regula-Face-API-Deployment or platform-engineering owner exactly how and
> when `arn:...:layer:ffmpeg:1` was created in the `921483706620`/`772479554838` accounts (this repo's `make
> deploy` run against those accounts directly, versus a SAR-based deploy) — not verifiable from either
> repo's Git history alone.

## Conventions

- **Australian/NZ English** in new documentation and comments (organisation, licence, colour) — the
  existing upstream README text is US-spelled in places (e.g. "License") and is left as-is rather than
  rewritten wholesale, per the "improve/reconcile only for real gaps" scope of this documentation pass.
- **Do not vendor or commit the fetched FFmpeg tarball or extracted binaries.** `build/` is `.gitignore`d;
  the Makefile always fetches from BtbN's GitHub release and checks the SHA-256 in `versions.mk`.
- **Treat `README.md` (root, MIT-focused, general usage) and `README-SAR.md` (SAR-listing-focused, shown
  inside the AWS Serverless Application Repository console) as two different audiences for the same
  artefact, not duplicates to be merged.** `template.yaml`'s `Metadata.AWS::ServerlessRepo::Application.ReadmeUrl`
  points at `README-SAR.md` specifically — that file is rendered by AWS itself as the SAR listing's
  description page, and is deliberately short. `README.md` is the GitHub-facing landing page with build/deploy
  instructions, licensing, and the LGPL fork pointer. Keep both, keep them each concise for their own
  audience, and only touch one when a fact in it is stale or wrong — do not fold one into the other.
- **The `LGPL version` pointer in `README.md`** (a community fork at
  `giusedroid/ffmpeg-aws-lambda-layer` on the `license/lgpl` branch, containing only LGPL-licensed FFmpeg
  components) is there for organisations concerned about GPL licensing obligations. This repo's own default
  build is **GPL** (per `template.yaml`'s `LicenseInfo: GPL-2.0-or-later` and the BtbN GPL build being GPLv3) — do not remove that pointer or imply this repo's own layer is LGPL-clean.

## Key Files

- `template.yaml` — the SAM template; the single `AWS::Serverless::LayerVersion` resource plus the
  `AWS::ServerlessRepo::Application` metadata block that drives the SAR listing.
- `versions.mk` — the pinned BtbN release, asset names and SHA-256 hashes per architecture.
- `Makefile` — fetch and verify FFmpeg → check → package → deploy, per `ARCH`. See [Build & Publish](#build--publish).
- `scripts/check-layer.sh` — functional check (frame count on irregular-timestamp WebM → MP4) run by `make check`.
- `README.md` — GitHub-facing usage/build/deploy/licensing doc.
- `README-SAR.md` — short description rendered inside the AWS Serverless Application Repository console
  (referenced by `template.yaml`'s `ReadmeUrl`).
- `LICENSE.txt` — licensing summary for this repo's own scripts (MIT) vs. the bundled FFmpeg binary (GPL).
- `example/` — a separate, standalone SAM application demonstrating layer consumption (thumbnail extraction
  from an uploaded video via S3 trigger). See [The `example/` directory](#the-example-directory).
- `docs/architecture.md` — build/publish/consume flow and a diagram of how the layer moves from this repo to
  a consuming Lambda.

## Git

- Default branch: **`master`** (not `main` — this repo predates the org's later `main`-default convention
  and, as an inherited fork, has not been renamed).
- Remote `origin` → GitHub (`Greengate-Fintech/ffmpeg-aws-lambda-layer`)
- No GitHub Actions workflows exist in this repository (no `.github/` directory at all) — there is no CI
  gate; run `make check ARCH=x86_64` and `make check ARCH=arm64` for any change to the build, and validate template changes by running `make deploy` against a real AWS account before merging.

## Security & Boundaries

- **Never commit the fetched FFmpeg tarball, extracted binaries, or anything under `build/`** — already
  `.gitignore`d; keep it that way.
- **Keep the FFmpeg build pinned, with a hash check.** `versions.mk` names one dated BtbN release and a
  SHA-256 per architecture. The check detects any change to the asset after pinning; the pinned hashes were
  cross-checked against BtbN's published `checksums.sha256` for that release at pin time. It does not prove
  BtbN's own build is trustworthy. Never replace the pin with a `latest` or `master` URL, and never skip the
  hash check. Both architectures must use the same FFmpeg version.
- **Never point `example/template-sar.yaml` (or any new consumer template) at the upstream third-party SAR
  application ARN (`arn:aws:serverlessrepo:us-east-1:145266761615:...`) as if it were Greengate-Fintech's
  own** — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question). If that ARN is still
  the one actually in use internally, treat it as an explicit third-party dependency (outside
  Greengate-Fintech's control/patch cadence) and flag it, rather than silently treating it as part of an
  in-house supply chain.
- **Respect the GPL obligations already documented in `LICENSE.txt`/`README.md`.** This repo's own
  packaging scripts are MIT, but the bundled FFmpeg/FFprobe binaries are GPL — do not describe the layer as
  a whole as "MIT licensed" in new documentation.
