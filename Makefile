include versions.mk

# Target architecture: x86_64 or arm64.
ARCH ?= x86_64

ifeq ($(ARCH),x86_64)
STACK_NAME ?= ffmpeg-lambda-layer
LAYER_NAME ?= ffmpeg
else ifeq ($(ARCH),arm64)
STACK_NAME ?= ffmpeg-arm64-lambda-layer
LAYER_NAME ?= ffmpeg-arm64
else
$(error ARCH must be x86_64 or arm64, got '$(ARCH)')
endif

FFMPEG_ASSET = $(FFMPEG_ASSET_$(ARCH))
# Expected SHA-256 of the download; override only to test the check itself.
SHA256 ?= $(FFMPEG_SHA256_$(ARCH))
FFMPEG_URL = https://github.com/BtbN/FFmpeg-Builds/releases/download/$(BTBN_RELEASE)/$(FFMPEG_ASSET)
LAYER_DIR = build/$(ARCH)/layer

# On a host of a different architecture the binaries under test run in an
# Amazon Linux 2023 container under QEMU (needs Docker with binfmt installed:
# docker run --privileged --rm tonistiigi/binfmt --install arm64).
DOCKER ?= docker
ifeq ($(ARCH),arm64)
ifneq ($(shell uname -m),aarch64)
CHECK_RUNNER = $(DOCKER) run --rm --platform linux/arm64 -v $(CURDIR):$(CURDIR) -v /tmp:/tmp -w /tmp amazonlinux:2023
endif
endif

clean:
	rm -rf build

$(LAYER_DIR)/bin/ffmpeg:
	rm -rf build/$(ARCH)/extract
	mkdir -p build/$(ARCH)/extract $(LAYER_DIR)/bin
	curl -fsSL -o build/$(ARCH)/$(FFMPEG_ASSET) $(FFMPEG_URL)
	echo "$(SHA256)  build/$(ARCH)/$(FFMPEG_ASSET)" | sha256sum -c -
	tar -xJf build/$(ARCH)/$(FFMPEG_ASSET) -C build/$(ARCH)/extract --strip-components=2 --wildcards '*/bin/ffmpeg' '*/bin/ffprobe'
	mv build/$(ARCH)/extract/ffmpeg build/$(ARCH)/extract/ffprobe $(LAYER_DIR)/bin

build: $(LAYER_DIR)/bin/ffmpeg

check: build
	RUNNER='$(CHECK_RUNNER)' scripts/check-layer.sh $(LAYER_DIR)/bin

# template.yaml points at build/layer; the per-architecture copy points at its own layer directory.
build/$(ARCH)/template.yaml: template.yaml
	mkdir -p build/$(ARCH)
	sed 's|ContentUri: build/layer|ContentUri: layer|' $< > $@

build/$(ARCH)/output.yaml: build/$(ARCH)/template.yaml $(LAYER_DIR)/bin/ffmpeg
	aws cloudformation package --template $< --s3-bucket $(DEPLOYMENT_BUCKET) --output-template-file $@

deploy: build/$(ARCH)/output.yaml
	aws cloudformation deploy --template $< --stack-name $(STACK_NAME) \
		--parameter-overrides LayerName=$(LAYER_NAME) Architecture=$(ARCH)
	aws cloudformation describe-stacks --stack-name $(STACK_NAME) --query Stacks[].Outputs --output table

deploy-example:
	cd example && \
		make deploy DEPLOYMENT_BUCKET=$(DEPLOYMENT_BUCKET) LAYER_STACK_NAME=$(STACK_NAME)

.PHONY: clean build check deploy deploy-example
