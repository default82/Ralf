#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
BUILD_SCRIPT="${REPO_ROOT}/automation/ralf/build_local_ai_lxc.sh"

if [[ ! -x "${BUILD_SCRIPT}" ]]; then
  echo "Expected build script '${BUILD_SCRIPT}' to be executable" >&2
  exit 1
fi

output="$(${BUILD_SCRIPT} --dry-run)"

if [[ -z "${output}" ]]; then
  echo "Dry run produced no output" >&2
  exit 1
fi

[[ "${output}" == *"==> Local AI LXC build plan"* ]] || {
  echo "Missing build plan banner in output" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"[dry-run] Would execute: pct create"* || "${output}" == *"[DRY-RUN] Would execute: pct create"* ]] || {
  echo "Missing pct create dry-run marker" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"[dry-run] Would execute: pct exec"* || "${output}" == *"[DRY-RUN] Would execute: pct exec"* ]] || {
  echo "Missing pct exec dry-run marker" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"==> Dry run complete"* ]] || {
  echo "Missing completion banner" >&2
  echo "${output}" >&2
  exit 1
}

printf '%s\n' "${output}"
