THEOS ?= $(HOME)/theos
THEOS_OUTPUT_DIR := $(abspath $(CURDIR)/../../../build/Theos/lycorined)
_THEOS_LOCAL_DATA_DIR := $(THEOS_OUTPUT_DIR)
TARGET := iphone:clang:latest:17.6
ARCHS = arm64
TARGET_CODESIGN := /usr/bin/codesign

include $(THEOS)/makefiles/common.mk

TOOL_NAME = lycorined

lycorined_FILES = \
    main.m \
    $(wildcard Bootstrap/*.m Bootstrap/*.c) \
    $(wildcard Cloning/*.m Cloning/Apps/*.m) \
    Core/Paths.m Core/Spawn.m Core/utils.m \
    $(wildcard Cryptex/*.swift) \
    $(wildcard IPC/*.m) \
    $(wildcard Patching/*.m Patching/*.c Patching/*.S) \
    $(wildcard Reboot/*.m) \
    ../Hooks/Shared/ClonePaths.c \
    ../Hooks/Shared/LaunchDaemon.m
lycorined_CFLAGS = -fobjc-arc -fblocks -I$(CURDIR) -fmodules-cache-path=$(THEOS_OUTPUT_DIR)/modules
lycorined_SWIFTFLAGS = -swift-version 5
lycorined_FRAMEWORKS = Foundation IOKit
lycorined_CFLAGS += -IPatching/include
lycorined_LDFLAGS = $(CURDIR)/Patching/lib/libchoma.a
Reboot/UserspaceReboot.m_CFLAGS = -fno-objc-arc
lycorined_CODESIGN_FLAGS = -f -s - --entitlements $(CURDIR)/entitlements.plist --generate-entitlement-der

include $(THEOS_MAKE_PATH)/tool.mk

.PHONY: cryptex-install
cryptex-install: all
	@test -n "$(CRYPTEX_ROOT)"
	mkdir -p $(CRYPTEX_ROOT)/usr/bin
	install -m 755 $(THEOS_OUTPUT_DIR)/obj/$(TOOL_NAME) $(CRYPTEX_ROOT)/usr/bin/$(TOOL_NAME)
	mkdir -p $(CRYPTEX_ROOT)/usr/libexec/lycorine/Entitlements $(CRYPTEX_ROOT)/usr/libexec/lycorine/Hooks
	install -m 755 Cloning/Tools/ldid Cloning/Tools/cryptexctl Cloning/Tools/trustcachectl $(CRYPTEX_ROOT)/usr/libexec/lycorine/
	install -m 644 Cloning/Entitlements/*.plist $(CRYPTEX_ROOT)/usr/libexec/lycorine/Entitlements/
	@for hook in generalhook safemode PreferenceLoader27 xpcproxyhook launchdhook lsdhook; do \
	    $(MAKE) -C ../Hooks/$$hook all DEBUG=0 || exit $$?; \
	    install -m 755 $(abspath $(CURDIR)/../../../build/Theos)/$$hook/obj/$$hook.dylib \
	        $(CRYPTEX_ROOT)/usr/libexec/lycorine/Hooks/$$hook.dylib || exit $$?; \
	done
	$(MAKE) -C ../Hooks/faked all DEBUG=0 || exit $$?
	install -m 755 $(abspath $(CURDIR)/../../../build/Theos)/faked/obj/faked \
	    $(CRYPTEX_ROOT)/usr/libexec/lycorine/faked || exit $$?
