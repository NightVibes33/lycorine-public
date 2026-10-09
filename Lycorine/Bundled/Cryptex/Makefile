# Reconstructed overlay: original public targets plus read-only diagnostics
# and documented research-device-only personalization.
SHELL := /bin/zsh
.DEFAULT_GOAL := all
PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPT := /bin/zsh $(PROJECT_DIR)/scripts/build.sh

.PHONY: all doctor fetch build audit image personalize bundle clean distclean
all: image

doctor fetch build audit image personalize bundle clean distclean:
	@$(SCRIPT) $@
