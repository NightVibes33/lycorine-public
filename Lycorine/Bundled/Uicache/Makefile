ROOT := $(abspath ../../..)
BUILD := $(ROOT)/build/Uicache
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CC := $(shell xcrun --sdk iphoneos -f clang)
OVERLAY := ../Cryptex/bootstrap/overlay/var/jb/usr/bin/uicache
ENTITLEMENTS := ../Cryptex/config/uicache.entitlements.plist

.PHONY: all overlay
all: $(BUILD)/uicache

$(BUILD)/uicache: uicache.m $(ENTITLEMENTS) Makefile
	mkdir -p $(BUILD)
	$(CC) -isysroot $(SDK) -target arm64-apple-ios17.6 -fobjc-arc -fmodules -O2 -Wall \
		-fmodules-cache-path=$(BUILD)/modules \
		-framework Foundation -framework MobileCoreServices -framework Security \
		uicache.m -o $@
	codesign --force --sign - --timestamp=none --pagesize 4096 \
		--entitlements $(ENTITLEMENTS) --generate-entitlement-der $@
	codesign --verify --strict $@

overlay: all
	install -m 755 $(BUILD)/uicache $(OVERLAY)
