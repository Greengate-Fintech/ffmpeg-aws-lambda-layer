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
# Expected SHA-256 of the download. FFMPEG_SHA256_OVERRIDE exists only to test the
# check itself; the distinct name keeps an unrelated SHA256 environment variable out.
FFMPEG_SHA256 = $(or $(FFMPEG_SHA256_OVERRIDE),$(FFMPEG_SHA256_$(ARCH)))
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

# The layer holds bin/ffmpeg, bin/ffprobe and lib/ with each FFmpeg shared library once,
# as a regular file named by its soname (libavcodec.so.62), which is what the binaries
# load. The .so and full-version names are symlinks, and aws cloudformation package
# would zip each link as another full copy. bin/ moves in last, so a failed build
# leaves no bin/ffmpeg and the next run starts again. The tarball's file dates predate
# versions.mk, so bin/ffmpeg is touched to mark the build current.
$(LAYER_DIR)/bin/ffmpeg: versions.mk
	rm -rf build/$(ARCH)/extract $(LAYER_DIR)
	mkdir -p build/$(ARCH)/extract $(LAYER_DIR)
	curl -fsSL -o build/$(ARCH)/$(FFMPEG_ASSET) $(FFMPEG_URL)
	echo "$(FFMPEG_SHA256)  build/$(ARCH)/$(FFMPEG_ASSET)" | sha256sum -c -
	tar -xJf build/$(ARCH)/$(FFMPEG_ASSET) -C build/$(ARCH)/extract --strip-components=1 --wildcards '*/bin/ffmpeg' '*/bin/ffprobe' '*/lib/*.so*'
	mkdir -p $(LAYER_DIR)/lib
	for lib in build/$(ARCH)/extract/lib/*.so.*; do \
		case "$${lib##*.so.}" in *.*) ;; *) cp -L "$$lib" $(LAYER_DIR)/lib/ ;; esac; \
	done
	mv build/$(ARCH)/extract/bin $(LAYER_DIR)
	touch $@

build: $(LAYER_DIR)/bin/ffmpeg

check: build check-template
	RUNNER='$(CHECK_RUNNER)' scripts/check-layer.sh $(LAYER_DIR)

# The per-architecture template must find everything package uploads next to it.
check-template: build/$(ARCH)/template.yaml $(LAYER_DIR)/bin/ffmpeg
	scripts/check-template-paths.sh build/$(ARCH)/template.yaml

# template.yaml points at build/layer; the per-architecture copy points at its own layer directory.
# package resolves ReadmeUrl and LicenseUrl relative to the template, so copy those files next to it.
build/$(ARCH)/README-SAR.md build/$(ARCH)/LICENSE.txt: build/$(ARCH)/%: %
	mkdir -p build/$(ARCH)
	cp $< $@

build/$(ARCH)/template.yaml: template.yaml build/$(ARCH)/README-SAR.md build/$(ARCH)/LICENSE.txt
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

.PHONY: clean build check check-template deploy deploy-example
