THEOS ?= $(HOME)/theos
TARGET := iphone:clang:latest:17.0
ARCHS = arm64e arm64
THEOS_PACKAGE_SCHEME = rootless
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../../build/Theos/PreferenceLoader27)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = PreferenceLoader27
PreferenceLoader27_FILES = loader.m bridge.m bridge.swift Support/PLHeap.m Support/PLSwiftMeta.m Support/PLSwiftString.swift
PreferenceLoader27_CFLAGS = -fobjc-arc -fblocks -O2 -I$(CURDIR)/Support
PreferenceLoader27_FRAMEWORKS = Foundation UIKit QuartzCore
TARGET_CODESIGN := /usr/bin/codesign
TARGET_CODESIGN_FLAGS := -s -

include $(THEOS_MAKE_PATH)/library.mk
