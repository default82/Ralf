#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
BUILD_SCRIPT="${REPO_ROOT}/automation/ralf/build_local_ai_lxc.sh"

if [[ ! -x "${BUILD_SCRIPT}" ]]; then
  echo "Expected build script '${BUILD_SCRIPT}' to be executable" >&2
  exit 1
fi

output="$(sudo bash "${BUILD_SCRIPT}" --dry-run)"

if [[ -z "${output}" ]]; then
  echo "Dry run produced no output" >&2
  exit 1
fi

[[ "${output}" == *"# Managed by build_local_ai_lxc.sh"* ]] || {
  echo "Missing configuration header in output" >&2
  echo "${output}" >&2
  exit 1
}

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

[[ "${output}" == *"[dry-run] Would execute: pct set"* ]] || {
  echo "Missing pct set reconciliation step" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"[dry-run] Would execute: pct resize"* ]] || {
  echo "Missing pct resize dry-run marker" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"pct push"*"/usr/local/bin/ralf-ai"* ]] || {
  echo "Missing ralf-ai wrapper upload step" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"chmod 0755 /usr/local/bin/ralf-ai"* ]] || {
  echo "Missing ralf-ai chmod step" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"/usr/local/bin/ralf-ai --help"* ]] || {
  echo "Missing ralf-ai help invocation" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"ralf-lxc-reconcile"* ]] || {
  echo "Missing reconcile hook installation output" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"==> Dry run complete"* ]] || {
  echo "Missing completion banner" >&2
  echo "${output}" >&2
  exit 1
}

printf '%s\n' "${output}"
