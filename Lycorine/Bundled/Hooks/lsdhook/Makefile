THEOS ?= $(HOME)/theos
TARGET := iphone:clang:latest:17.0
ARCHS = arm64e arm64
THEOS_PACKAGE_SCHEME = rootless
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../../build/Theos/lsdhook)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = lsdhook
lsdhook_FILES = $(wildcard *.m)
lsdhook_CFLAGS = -fobjc-arc -O2 -fmodules-cache-path=$(THEOS_OUTPUT_DIR)/modules
lsdhook_FRAMEWORKS = Foundation
TARGET_CODESIGN := /usr/bin/codesign
TARGET_CODESIGN_FLAGS := -s -

include $(THEOS_MAKE_PATH)/library.mk
