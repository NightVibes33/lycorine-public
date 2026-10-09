THEOS ?= $(HOME)/theos
TARGET := iphone:clang:latest:15.0
ARCHS = arm64e arm64
THEOS_PACKAGE_SCHEME = rootless
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../../build/Theos/generalhook)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = generalhook

# Use Apple's ad-hoc signer instead of Theos' default Darwin signer (ldid).
TARGET_CODESIGN := /usr/bin/codesign
TARGET_CODESIGN_FLAGS := -s -

$(LIBRARY_NAME)_FILES = $(wildcard *.c *.m ../Shared/Sandbox/*.c) ../Shared/Log.c ../Shared/litehook.c
$(LIBRARY_NAME)_CFLAGS = -fno-objc-arc -Wno-error -O3 -fmodules-cache-path=$(THEOS_OUTPUT_DIR)/modules
$(LIBRARY_NAME)_LDFLAGS = -L./ -lbsm
after-all::
	cp $(THEOS_OBJ_DIR)/generalhook.dylib .
include $(THEOS_MAKE_PATH)/library.mk
