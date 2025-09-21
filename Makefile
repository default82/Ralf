SHELL := /usr/bin/env bash

.PHONY: lint test build

lint:
	./tests/shellcheck.sh

test: lint
	./tests/smoke_build_lxc.sh
	./tests/smoke_wrapper.sh

BUILD_FLAGS ?= --dry-run

build:
	sudo bash automation/ralf/build_local_ai_lxc.sh $(BUILD_FLAGS)
