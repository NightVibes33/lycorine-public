SHELL := /bin/zsh
.DEFAULT_GOAL := all

PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPT := /bin/zsh $(PROJECT_DIR)/scripts/build.sh

.PHONY: all fetch build image bundle clean distclean

all: image

fetch:
	@$(SCRIPT) fetch

build:
	@$(SCRIPT) build

image:
	@$(SCRIPT) image

bundle:
	@$(SCRIPT) bundle

clean:
	@$(SCRIPT) clean

distclean:
	@$(SCRIPT) distclean
