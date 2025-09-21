#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed; skipping lint" >&2
  exit 0
fi

mapfile -t scripts < <(find "${REPO_ROOT}" -type f \( -name '*.sh' -o -name 'ralf-ai' \))

if [[ ${#scripts[@]} -eq 0 ]]; then
  echo "No shell scripts found"
  exit 0
fi

shellcheck "${scripts[@]}"
