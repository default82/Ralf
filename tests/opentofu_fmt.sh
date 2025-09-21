#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
TARGET_DIR="${REPO_ROOT}/infrastructure/opentofu"

if ! command -v tofu >/dev/null 2>&1; then
  echo "OpenTofu (tofu) is not installed; skipping fmt check" >&2
  exit 0
fi

if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "No OpenTofu configuration found; skipping fmt check" >&2
  exit 0
fi

tofu fmt -check -recursive "${TARGET_DIR}"
