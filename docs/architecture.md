# Architecture

This document describes how the FFmpeg Lambda layer in this repository is **built, packaged, published,
and consumed** — there is no request-processing runtime of its own to diagram, since the repo's only output
is a Lambda layer version (a `.zip` of static binaries plus CloudFormation/SAR metadata), not a service.

See [CLAUDE.md](../CLAUDE.md) for the full project overview, conventions, and open questions
(in particular the [upstream-vs-fork identity question](../CLAUDE.md#upstream-vs-fork-identity-open-question)
referenced throughout this document).

## Why there is no `failure-scenarios.md`

Several sibling repositories in this org (e.g. `verifime-report-delivery-lambda`,
`risk-assessment-notification-producer-lambda`) pair `architecture.md` with a `failure-scenarios.md`
documenting SQS/SNS retry semantics, DLQ behaviour, and partial-batch failure handling. **That document
doesn't apply here.** This repo has no message queue, no event source mapping, and no runtime request path
of its own — it is a build/publish artefact. There is nothing that "retries" or "redelivers." The failure
modes that actually matter for a repo like this are **build-time** and **publish-time**, not
request-time, so they are covered briefly below instead of in a separate document.

## Build, Package, and Publish Flow

```mermaid
flowchart TD
    subgraph SRC["Upstream binary source (not in this repo)"]
        BTBN["BtbN/FFmpeg-Builds dated autobuild release<br/>linux64-gpl and linuxarm64-gpl, 8.1 branch<br/>(pinned tag, asset and SHA-256 in versions.mk)"]
    end

    subgraph REPO["This repo: local build (no CI)"]
        FETCH["make build ARCH=x86_64|arm64<br/>curl, sha256sum -c, tar x"]
        BIN["build/ARCH/layer/bin/<br/>ffmpeg, ffprobe"]
        CHK["make check<br/>scripts/check-layer.sh"]
        TPL["template.yaml<br/>AWS::Serverless::LayerVersion<br/>+ AWS::ServerlessRepo::Application metadata"]
        PKG["aws cloudformation package<br/>uploads build/ARCH/layer to S3"]
    end

    subgraph AWS["Target AWS account (operator-supplied)"]
        S3B["S3: DEPLOYMENT_BUCKET"]
        CFN["aws cloudformation deploy<br/>stack: ffmpeg-lambda-layer (x86_64)<br/>or ffmpeg-arm64-lambda-layer (arm64)"]
        LAYER["Lambda Layer Version<br/>arn:aws:lambda:REGION:ACCOUNT:layer:ffmpeg:N<br/>or layer:ffmpeg-arm64:N"]
    end

    subgraph SAR["AWS Serverless Application Repository (unconfirmed for this fork)"]
        SARAPP["SAR application: ffmpeg-lambda-layer<br/>upstream ARN account 145266761615"]
    end

    BTBN -->|"curl (every clean build)"| FETCH
    FETCH --> BIN
    BIN --> CHK
    CHK --> TPL
    TPL --> PKG
    PKG --> S3B
    S3B --> CFN
    CFN --> LAYER
    LAYER -.->|"manual SAR publish step<br/>not scripted in this repo, unconfirmed"| SARAPP

    style SAR stroke-dasharray: 5 5
    style SARAPP fill:#f59e0b,color:#000
```

Notes on the diagram:

- The dashed edge into the SAR box reflects that **publishing a new SAR application version is a manual
  step outside this repo's `Makefile`** — `make deploy` only produces a private CloudFormation stack with a
  layer version in whatever account/region the operator targets. Whether this fork has ever actually been
  re-published as Greengate-Fintech's own SAR application (as opposed to consumers using the original
  `serverlesspub`-owned SAR listing, account `145266761615`) is unconfirmed — see
  [CLAUDE.md's open question](../CLAUDE.md#upstream-vs-fork-identity-open-question).
- The FFmpeg binary source is a **pinned, dated BtbN release** for each architecture. `versions.mk` holds
  the release tag, the asset names and the SHA-256 of each, and the `Makefile` stops before extracting if a
  download does not match. Two builds on different days package the same binaries.
- `make check` converts an irregular-timestamp WebM to MP4 with the bundled `ffmpeg` and fails if the output
  does not hold 95-100% of the input frames (FFmpeg 7.0.2 and older duplicate them; 7.1 and later do not).
- **To bump FFmpeg**, edit `versions.mk` (a newer autobuild on a release branch, hashes from that release's
  `checksums.sha256`), run `make check` for both architectures, then publish both layers.

## Consumption Flow (confirmed real consumer)

The only confirmed consumer of a deployed instance of this layer, found by searching every other repository
in the organisation, is `Regula-Face-API-Deployment`'s video-conversion Lambda. It does not depend on this
repo's source or Git history at all — only on a Lambda layer ARN that already exists in its own AWS
accounts, referenced by convention (see `Regula-Face-API-Deployment/lib/constants.ts:88,109`).

```mermaid
sequenceDiagram
    participant Upload as Client (video upload)
    participant S3 as S3 bucket (Regula session storage)
    participant Fn as ConvertFileFunction Lambda<br/>(Regula-Face-API-Deployment)
    participant Layer as ffmpeg Lambda layer<br/>(/opt/bin, this repo's artefact)

    Upload->>S3: PUT video.mp4
    S3->>Fn: ObjectCreated event
    Fn->>S3: download source video to /tmp
    Fn->>Layer: spawn /opt/bin/ffmpeg -i input -f mp4 output
    Layer-->>Fn: converted MP4 written to /tmp
    Fn->>S3: upload converted file, mark metadata converted=1
```

`Regula-Face-API-Deployment` pins a specific layer **version** (`:1` at the time of writing; the 8.x layers are `ffmpeg:2` and `ffmpeg-arm64:1`) by ARN
(`lib/regula-face-api-s3-bucket-stack.ts:121-125`, `lib/constants.ts:88,109`) in its own non-prod
(`921483706620`) and prod (`772479554838`) accounts, region `ap-southeast-2`. Publishing a new layer version
from this repo does **not** automatically reach that consumer — it requires a separate CDK change in
`Regula-Face-API-Deployment` to bump the ARN's version suffix. See
[CLAUDE.md § Ecosystem Position](../CLAUDE.md#ecosystem-position) for the full detail and the open question
about how that layer version was originally created (manual `make deploy` vs. a SAR-based deploy).

`example/src/index.js` in this repo demonstrates the same `/opt/bin/ffmpeg` invocation pattern
(thumbnail extraction rather than transcoding) against the example stack's own layer reference — see
[CLAUDE.md § The `example/` directory](../CLAUDE.md#the-example-directory).

## Build/Publish Failure Modes

Since there is no runtime request path, "failure scenarios" for this repo are about the build and publish
steps going wrong, not about message redelivery or retries:

| Failure mode | Cause | Effect | Mitigation in this repo |
|---|---|---|---|
| Tampered or changed download | The BtbN asset for the pinned tag differs from the hash in `versions.mk` (or is deleted: BtbN removes old autobuilds) | `make build` stops at `sha256sum -c` before extracting; nothing reaches AWS | The hash check. If the release has been removed, bump `versions.mk` to a current release (see above) |
| Upstream URL unavailability | `curl` to `github.com` fails (network issue) | `make deploy` fails at the `build/ARCH/layer/bin/ffmpeg` step before anything reaches AWS; no partial layer is deployed, since `mv` is the last step | A failed `curl` or hash check leaves no `build/ARCH/layer/bin/ffmpeg`, so the next run retries cleanly |
| Limited automated tests, no CI | `make check` covers the frame-count behaviour only; no `.github/workflows/` | A change to `template.yaml` (e.g. a bad `ContentUri`) is only caught by a human running `make deploy` against a real AWS account, or by the consuming Lambda failing at cold start (`ENOENT: /opt/bin/ffmpeg`) | `make check` for the binaries; none for the template. Any CI addition should be scoped deliberately |
| Runtime and glibc compatibility | `template.yaml` declares `nodejs24.x`, `nodejs22.x`, `python3.13`; the BtbN binaries need glibc 2.28 or later | The layer works on Amazon Linux 2023 runtimes and fails with a glibc error on Amazon Linux 2 runtimes | Declared runtimes are Amazon Linux 2023 only |
| Cross-account ARN drift | A layer version deployed via `make deploy` is account/region-specific (`arn:aws:lambda:REGION:ACCOUNT:layer:ffmpeg:N`) | If this repo is redeployed into a *different* account than a consumer expects (e.g. a new environment), the consumer's hard-coded ARN (see `Regula-Face-API-Deployment/lib/constants.ts`) will not resolve — there is no cross-account/cross-region layer sharing configured anywhere in this repo's `template.yaml` | None — `AWS::Serverless::LayerVersion` here has no `LayerPermission`/cross-account grant resource; if cross-account sharing is ever needed, that is new work, not an existing capability |

## Open Questions

> **TODO(owner):** Whether this fork has ever been published as Greengate-Fintech's own AWS Serverless
> Application Repository listing (with its own account-scoped ARN and `SemanticVersion` lineage), or whether
> all internal consumption to date has been via a one-off `make deploy` direct to a target account (bypassing
> SAR entirely) — see [CLAUDE.md](../CLAUDE.md#upstream-vs-fork-identity-open-question). The confirmed
> consumer's ARN shape (a plain regional Lambda layer ARN, not a SAR application reference) is consistent
> with the latter, but this is not verified against deployment history.
