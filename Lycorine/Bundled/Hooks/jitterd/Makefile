THEOS ?= $(HOME)/theos
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../../build/Theos/jitterd)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
TARGET := iphone:clang:latest:17.6
ARCHS = arm64e arm64
TARGET_CODESIGN := /usr/bin/codesign

include $(THEOS)/makefiles/common.mk

TOOL_NAME = jitterd

jitterd_FILES = $(wildcard *.c *.m) ../Shared/Log.c
jitterd_CFLAGS = -fno-objc-arc -O3 -fmodules-cache-path=$(THEOS_OUTPUT_DIR)/modules
jitterd_LDFLAGS = -lbsm
jitterd_CODESIGN_FLAGS = -f -s - --entitlements $(CURDIR)/../../Cryptex/config/jitterd.entitlements.plist --generate-entitlement-der

include $(THEOS_MAKE_PATH)/tool.mk

.PHONY: cryptex-install
cryptex-install: all
	@test -n "$(CRYPTEX_ROOT)"
	install -m 755 $(THEOS_OUTPUT_DIR)/obj/$(TOOL_NAME) $(CRYPTEX_ROOT)/usr/bin/$(TOOL_NAME)
