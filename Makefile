
SHELL := /usr/bin/env bash

.PHONY: lint test build portal-build

lint: ## Shellcheck über Skripte
	(shellcheck automation/**/*.sh || true)

test: ## Smoke-Tests (Dry-Runs)
	bash tests/smoke_build_lxc.sh
	bash tests/smoke_wrapper.sh

build: ## LXC bauen (ohne Dry-Run)
	sudo bash automation/ralf/build_local_ai_lxc.sh

portal-build: ## Build the Next.js-based portal UI
	cd portal/ui && pnpm install --frozen-lockfile && pnpm run build
