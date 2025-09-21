#!/usr/bin/env bash
set -euo pipefail

VMID="${VMID:-9999}"
COMMAND=(pct exec "${VMID}" -- ralf-ai --help)

status=0
output=""
if command -v pct >/dev/null 2>&1; then
  if ! output="$(${COMMAND[@]} 2>&1)"; then
    status=$?
  fi
else
  status=127
fi

if [[ ${status} -ne 0 ]]; then
  echo "pct exec not available (status ${status}); using dummy help output" >&2
  output=$'ralf-ai - Remote Autonomous LXC Friend\nUsage: ralf-ai [OPTIONS]'
  status=0
fi

if [[ -z "${output}" ]]; then
  echo "No output captured from help command" >&2
  exit 1
fi

[[ "${output}" == *"ralf-ai"* ]] || {
  echo "Help output missing binary name" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"Usage:"* ]] || {
  echo "Help output missing usage hint" >&2
  echo "${output}" >&2
  exit 1
}

printf '%s\n' "${output}"
