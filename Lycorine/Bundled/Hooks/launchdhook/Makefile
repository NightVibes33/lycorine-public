THEOS ?= $(HOME)/theos
TARGET := iphone:clang:latest:17.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = rootless
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../../build/Theos/launchdhook)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = launchdhook
launchdhook_FILES = $(wildcard *.c *.m ../Shared/Spawn/*.c ../Shared/Spawn/*.m \
    ../Shared/Injection/*.c ../Shared/Trust/*.c ../Shared/JIT/*.c) \
    ../Shared/ClonePaths.c ../Shared/Log.c ../Shared/litehook.c \
    ../Shared/LaunchDaemon.m
launchdhook_CFLAGS = -fobjc-arc -fblocks -O2 -fmodules-cache-path=$(THEOS_OUTPUT_DIR)/modules
launchdhook_FRAMEWORKS = Foundation IOKit
launchdhook_LDFLAGS = -lsandbox
TARGET_CODESIGN := /usr/bin/codesign
TARGET_CODESIGN_FLAGS := -s -

include $(THEOS_MAKE_PATH)/library.mk
