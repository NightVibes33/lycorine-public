THEOS ?= $(HOME)/theos
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../../build/Theos/faked)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
TARGET := iphone:clang:latest:17.6
ARCHS = arm64e
TARGET_CODESIGN := /usr/bin/codesign

include $(THEOS)/makefiles/common.mk

TOOL_NAME = faked

faked_FILES = faked.m ../Shared/ClonePaths.c
faked_CFLAGS = -fblocks -O2 -fmodules-cache-path=$(THEOS_OUTPUT_DIR)/modules
faked_CODESIGN_FLAGS = -f -i com.apple.xpc.launchd -s - --entitlements $(CURDIR)/entitlements.plist --generate-entitlement-der
faked_LDFLAGS = -lsandbox

include $(THEOS_MAKE_PATH)/tool.mk
