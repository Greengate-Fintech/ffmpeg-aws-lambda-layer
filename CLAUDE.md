# Instructions for AI agents working on this codebase

## Project Overview

`ffmpeg-aws-lambda-layer` packages a static-binary build of **FFmpeg**/**FFprobe** (from
[John Van Sickle's static builds](https://johnvansickle.com/ffmpeg/)) as an **AWS Lambda layer**, using
AWS SAM (`AWS::Serverless-2016-10-31`). It is a **build/publish artefact repository**, not a running
service: there is no handler code here that executes on every invocation of some Lambda — the only
"product" is the layer's `.zip` content (`ffmpeg`/`ffprobe` binaries under `bin/`) and the
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
| Binary source | `https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz` — fetched fresh on every `make` build, not vendored/pinned in this repo |
| FFmpeg version bundled | 4.1.3, per `template.yaml`'s `Metadata.AWS::ServerlessRepo::Application.Description` and `README-SAR.md` — this is a **documentation claim, not an enforced pin** (see [Build & Publish](#build--publish)) |
| Compatible runtimes | `nodejs10.x`, `python3.6`, `ruby2.5`, `java8`, `go1.x` (`template.yaml`'s `CompatibleRuntimes`) — all now end-of-life/deprecated Lambda runtimes; the layer's binary content is runtime-agnostic (any Amazon Linux 2 Lambda can use it), but the declared compatibility list has not been updated since the original 2019 publish |
| Distribution | AWS Serverless Application Repository (SAR), application `ffmpeg-lambda-layer` — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question) |
| License | Layer packaging (this repo's scripts): MIT. FFmpeg itself: GPLv2.1+; John Van Sickle's static build: GPLv3 (see `LICENSE.txt`, `README.md`) |
| Output location | `AWS::Serverless::LayerVersion` in `build/layer` (Makefile fetches binaries there before `sam`/`cloudformation package` runs) |

Full build/publish/consume flow, including a diagram: [docs/architecture.md](docs/architecture.md).

## Build & Publish

```bash
make deploy DEPLOYMENT_BUCKET=<your-s3-bucket>       # build + package + deploy the layer stack
make deploy-example DEPLOYMENT_BUCKET=<your-s3-bucket>   # build + deploy the example consumer stack
make clean                                            # remove build/ (forces a re-fetch of the FFmpeg tarball)
```

There is no `make test`, `make lint`, or `make build` target that runs independently of `deploy` — `make
deploy` is the only entry point, and it always re-downloads the FFmpeg tarball on a clean `build/` (see
`Makefile`'s `build/layer/bin/ffmpeg` target). There are no automated tests in this repository.

Key `Makefile` targets, in dependency order:
1. `build/layer/bin/ffmpeg` — `curl`s the **latest** `ffmpeg-release-amd64-static.tar.xz` from John Van
   Sickle's site and extracts `ffmpeg`/`ffprobe` into `build/layer/bin/`. **This target is not tied to any
   specific FFmpeg release** — "latest" as of the wire is whatever John Van Sickle's server currently serves,
   not necessarily the 4.1.3 documented in `README.md`/`README-SAR.md`/`template.yaml`. Re-running `make
   deploy` after a `make clean` can silently pull in a newer FFmpeg build than the one the repo's own
   documentation and SAR listing claim to ship.
2. `build/output.yaml` — `aws cloudformation package` uploads `build/layer` to `$(DEPLOYMENT_BUCKET)` and
   rewrites `template.yaml`'s `ContentUri` to the resulting S3 object.
3. `deploy` — `aws cloudformation deploy` of the packaged template, stack name `$(STACK_NAME)` (default
   `ffmpeg-lambda-layer`), then prints the stack's `Outputs` (the layer's `LayerVersion` ARN).

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
application. Because `Regula-Face-API-Deployment` pins layer **version 1** by ARN, a new layer version
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
  the Makefile always fetches fresh from John Van Sickle's site.
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
  build is **GPL** (per `template.yaml`'s `LicenseInfo: GPL-2.0-or-later` and the John Van Sickle static
  build being GPLv3) — do not remove that pointer or imply this repo's own layer is LGPL-clean.

## Key Files

- `template.yaml` — the SAM template; the single `AWS::Serverless::LayerVersion` resource plus the
  `AWS::ServerlessRepo::Application` metadata block that drives the SAR listing.
- `Makefile` — fetch FFmpeg → package → deploy. See [Build & Publish](#build--publish).
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
  gate; validate any change by running `make deploy` against a real AWS account before merging.

## Security & Boundaries

- **Never commit the fetched FFmpeg tarball, extracted binaries, or anything under `build/`** — already
  `.gitignore`d; keep it that way.
- **Never assume the bundled FFmpeg version is pinned.** The Makefile always fetches
  `ffmpeg-release-amd64-static.tar.xz` (John Van Sickle's rolling "latest static build" alias, not a
  version-numbered URL) — the documented "4.1.3" in `README.md`/`README-SAR.md`/`template.yaml` reflects
  whatever was current when those files were last written, not a guarantee about what a fresh `make deploy`
  will actually package today. If you need version-pinning or reproducible builds, that is a real gap in
  this repo's current design, not a solved problem — do not describe it as pinned in new documentation.
- **Never point `example/template-sar.yaml` (or any new consumer template) at the upstream third-party SAR
  application ARN (`arn:aws:serverlessrepo:us-east-1:145266761615:...`) as if it were Greengate-Fintech's
  own** — see [Upstream vs. fork identity](#upstream-vs-fork-identity-open-question). If that ARN is still
  the one actually in use internally, treat it as an explicit third-party dependency (outside
  Greengate-Fintech's control/patch cadence) and flag it, rather than silently treating it as part of an
  in-house supply chain.
- **Respect the GPL obligations already documented in `LICENSE.txt`/`README.md`.** This repo's own
  packaging scripts are MIT, but the bundled FFmpeg/FFprobe binaries are GPL — do not describe the layer as
  a whole as "MIT licensed" in new documentation.
