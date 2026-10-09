THEOS ?= $(HOME)/theos
TARGET := iphone:clang:latest:17.0
ARCHS = arm64e arm64
THEOS_PACKAGE_SCHEME = rootless
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../../build/Theos/safemode)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = safemode
safemode_FILES = main.m
safemode_CFLAGS = -fobjc-arc -fblocks -O2
safemode_FRAMEWORKS = Foundation UIKit
TARGET_CODESIGN := /usr/bin/codesign
TARGET_CODESIGN_FLAGS := -s -

include $(THEOS_MAKE_PATH)/library.mk
