SHELL := /bin/bash

.PHONY: lint test build

## Lint shell scripts in automation/
lint:
	shellcheck automation/**/*.sh || true

## Run smoke tests for build and wrapper
test:
	tests/smoke_build_lxc.sh
	tests/smoke_wrapper.sh

## Build the local AI LXC image
build:
	sudo bash automation/ralf/build_local_ai_lxc.sh
