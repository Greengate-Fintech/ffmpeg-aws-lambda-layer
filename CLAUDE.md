# Instructions for AI agents working on this codebase

## Read first: this is a public repository

This repository is a public fork of an open-source project. Anything you write here is published to
everyone, permanently: files, commit messages, branch names, PR titles and descriptions, issues and
review comments. Git history cannot be taken back.

- **Write it as generic open-source documentation.** Describe the layer and how anyone would use it.
- **Never include:** the name of the organisation hosting this fork, its AWS account IDs, internal
  repositories, systems, consumers, people, customers, private issue or ticket links, internal hostnames,
  or any secret. If a change is motivated by an internal problem, describe the public, technical cause
  (for example "ffmpeg 7.0.x duplicates frames on variable-frame-rate WebM") instead.
- **Keep internal context in the consuming project**, where its own repository and tracker are private.
- **Licensing:** this repository's files are MIT (see `LICENSE.txt`); a built layer is GPL 3.0 or later.
  Do not change licence statements without updating `LICENSE.txt`, `README.md` and `template.yaml`
  together, and do not describe the built layer as MIT or LGPL.
- **If you are unsure whether something is internal, leave it out and ask.**

## Project Overview

`ffmpeg-aws-lambda-layer` packages a shared-library build of **FFmpeg**/**FFprobe** (glibc-linked, needs glibc 2.28 or later; from
[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), pinned in `versions.mk`) as an **AWS Lambda layer**, using
AWS SAM (`AWS::Serverless-2016-10-31`). It is a **build/publish artefact repository**, not a running
service: there is no handler code here that executes on every invocation of some Lambda — the only
"product" is the layer's `.zip` content (`ffmpeg`/`ffprobe` binaries under `bin/`, the FFmpeg shared libraries under `lib/`) and the
CloudFormation/SAM template that wraps it.

**Origin**: this repository is a fork of [`serverlesspub/ffmpeg-aws-lambda-layer`](https://github.com/serverlesspub/ffmpeg-aws-lambda-layer)
(Gojko Adzic). Several artefacts still carry the upstream identity
verbatim — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question) below before assuming
any URL, ARN, or author byline in this repo belongs to the fork's maintainers.

There is no CI/CD in this repository — no `.github/workflows/`, only a `Makefile`. Building and publishing
the layer is a manual, local operation using the AWS CLI (see [Build & Publish](#build--publish)).

## What This Repo Is Not

- **Not a Lambda function repo.** There is no `RequestHandler`, no `exports.handler` at the top level of
  this repo (the `example/` directory's `index.js` handler is sample/reference code only, deployed by a
  *separate* example stack — see [The `example/` directory](#the-example-directory) below).
- **Not message-driven.** There is no SQS/SNS/EventBridge trigger, no retry/DLQ semantics, and therefore no
  `docs/failure-scenarios.md` in this repo (see the note in `docs/architecture.md` for why that document
  doesn't exist here, and what "failure" means for a build/publish artefact instead).
- **Not infrastructure for a running service.** The SAM template *is* the artefact's packaging, and
  stacks in *consumer* projects reference the resulting layer by ARN (see [Ecosystem Position](#ecosystem-position)).

## Architecture Summary

| Aspect | Detail |
|---|---|
| Packaging | AWS SAM (`template.yaml`), one resource: `AWS::Serverless::LayerVersion` |
| Binary source | A dated BtbN/FFmpeg-Builds autobuild release (`autobuild-YYYY-MM-DD-HH-MM`), GPL variant, release branch 8.1, one asset per architecture. The release tag, asset names and SHA-256 hashes are in `versions.mk`; the `Makefile` verifies the hash before extracting. No `latest` URL is used anywhere |
| FFmpeg version bundled | Set by `versions.mk` (`n8.1.3-17-gc389840894` at the time of writing, the same for x86_64 and arm64). Confirm with `build/<arch>/layer/bin/ffmpeg -version`. FFmpeg 7.1+ is required: earlier versions duplicate frames when converting browser-recorded WebM to MP4 without a frame-rate option. Evidence: releases 4.4.1, 6.1.1 and 7.0.2 were tested and duplicate frames when converting variable-frame-rate WebM (1 ms time base, no declared frame rate) to MP4 without a frame-rate option, while 7.1, 7.1.1, 8.0 and 8.0.1 keep the input frames; the change matches the upstream FFmpeg commit "lavf/movenc: mark mov/mp4 as supporting VFR". This repo's `make check` confirmed 7.0.2 failing (10390 frames from 300) and 8.1.3 passing (300). |
| Architectures | `x86_64` (stack `ffmpeg-lambda-layer`, layer `ffmpeg`) and `arm64` (stack `ffmpeg-arm64-lambda-layer`, layer `ffmpeg-arm64`), chosen with `make ... ARCH=` |
| Compatible runtimes | `nodejs24.x`, `nodejs22.x`, `python3.13` (`template.yaml`'s `CompatibleRuntimes`). The binaries are dynamically linked against glibc (needs 2.28 or later), so they suit Amazon Linux 2023 runtimes and not Amazon Linux 2 |
| Distribution | AWS Serverless Application Repository (SAR), application `ffmpeg-lambda-layer` — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question) |
| Licence | This repo's own files: MIT (upstream contributors; modifications Copyright (c) 2026 the contributors to this fork). FFmpeg: LGPL 2.1+ with optional GPL parts; the BtbN `gpl` build used here (`--enable-gpl --enable-version3`) makes a built layer GPL 3.0 or later (`template.yaml` `LicenseInfo: GPL-3.0-or-later`). See `LICENSE.txt` |
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
reference the **upstream** project's identity, and it is not confirmed whether this fork has ever been
re-published as its own SAR application, or whether users still consume the upstream SAR listing:

- `template.yaml`'s `Metadata.AWS::ServerlessRepo::Application` block: `Author: Gojko Adzic`,
  `HomePageUrl`/`SourceCodeUrl: https://github.com/serverlesspub/ffmpeg-aws-lambda-layer`,
  `SemanticVersion: 1.0.0`.
- `README.md` links to
  `https://serverlessrepo.aws.amazon.com/applications/arn:aws:serverlessrepo:us-east-1:145266761615:applications~ffmpeg-lambda-layer`
  — SAR account `145266761615` is the **upstream publisher's** AWS account (the upstream project's SAR
  listing), not an account belonging to this fork.
- `example/template-sar.yaml` deploys the example by referencing that same third-party SAR application ARN
  directly (`ApplicationId: arn:aws:serverlessrepo:us-east-1:145266761615:applications/ffmpeg-lambda-layer`).

> **TODO(owner):** Decide whether to publish this fork as its own SAR application (replacing the upstream
> `Author`, URLs and `SemanticVersion` in the template metadata and README), or to keep deploying it only as
> a private CloudFormation stack with `make deploy`. Until then the upstream identity above stays as is.

## The `example/` directory

`example/` is a **separate, self-contained SAM application** demonstrating how a consumer Lambda uses the
layer — it is not part of the layer's own build. It has its own `Makefile`, `template.yaml` (references the
layer stack's `Outputs.LayerVersion` by CloudFormation cross-stack lookup via `aws cloudformation
describe-stacks`, see `example/Makefile`'s `LAMBDA_LAYER` variable) and `template-sar.yaml` (references the
upstream SAR application ARN directly instead, see above).

`example/src/index.js` is a Node.js 10.x S3-triggered handler that downloads an uploaded video, shells out to
`/opt/bin/ffmpeg` (the path every Lambda layer's content is mounted at) to extract a thumbnail frame, and
uploads the result to a second bucket. This is the same `/opt/bin/ffmpeg` invocation pattern any consuming Lambda uses — see below.

## Ecosystem Position

This is a leaf repository: nothing in it depends on other projects, but a consuming Lambda depends on
**its output** (a deployed Lambda layer), not on this repo's source (there is no package/module import
relationship — only "some AWS account has an `ffmpeg` Lambda layer version deployed").

A consumer attaches the layer by its `LayerVersion` ARN (for example with
`lambda.LayerVersion.fromLayerVersionArn(...)` in CDK, or `Layers:` in SAM/CloudFormation) and calls
`/opt/bin/ffmpeg` and `/opt/bin/ffprobe`, the path any Lambda layer's content is mounted at. This is the
pattern `example/src/index.js` shows.

- Layer ARNs are account- and region-specific (`arn:aws:lambda:REGION:ACCOUNT:layer:ffmpeg:N`); a layer
  version published in one account or region does not exist in another.
- Publishing a new layer version does **not** update consumers that pin a version by ARN: each consumer
  must change its own ARN's version suffix. Publishing here is not sufficient to ship an FFmpeg update.
- The pinned FFmpeg 8.x build publishes as the `ffmpeg` (x86_64) and `ffmpeg-arm64` (arm64) layers; a
  consumer should attach the layer matching its function's architecture.

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
  build is **GPL 3.0 or later** (per `template.yaml`'s `LicenseInfo: GPL-3.0-or-later`, matching the BtbN `gpl` build's `--enable-gpl --enable-version3`) — do not remove that pointer or imply this repo's own layer is LGPL-clean.

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

- Default branch: **`master`** (not `main` — as an inherited fork, it has not been renamed).
- Remote `origin` → this fork on GitHub.
- No GitHub Actions workflows exist in this repository (no `.github/` directory at all) — there is no CI
  gate; run `make check ARCH=x86_64` and `make check ARCH=arm64` for any change to the build, and validate template changes by running `make deploy` against a real AWS account before merging.

## Security & Boundaries

- **Public repository:** see [Read first](#read-first-this-is-a-public-repository) at the top of this file.
- **Keep `LICENSE.txt` accurate** when the build source or its configure flags change: it states the
  MIT terms for this repo's files and the GPL 3.0-or-later status of a built layer.
- **Never commit the fetched FFmpeg tarball, extracted binaries, or anything under `build/`** — already
  `.gitignore`d; keep it that way.
- **Keep the FFmpeg build pinned, with a hash check.** `versions.mk` names one dated BtbN release and a
  SHA-256 per architecture. The check detects any change to the asset after pinning; the pinned hashes were
  cross-checked against BtbN's published `checksums.sha256` for that release at pin time. It does not prove
  BtbN's own build is trustworthy. Never replace the pin with a `latest` or `master` URL, and never skip the
  hash check. Both architectures must use the same FFmpeg version.
- **Never point `example/template-sar.yaml` (or any new consumer template) at the upstream third-party SAR
  application ARN (`arn:aws:serverlessrepo:us-east-1:145266761615:...`) as if it were this fork's own**
  — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question). If that ARN is still in
  use, treat it as an explicit third-party dependency (outside this fork's control and patch cadence) and
  flag it, rather than silently treating it as part of your own supply chain.
- **Respect the GPL obligations already documented in `LICENSE.txt`/`README.md`.** This repo's own
  packaging scripts are MIT, but the bundled FFmpeg/FFprobe binaries are GPL — do not describe the layer as
  a whole as "MIT licensed" in new documentation.
