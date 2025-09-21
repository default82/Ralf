#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${1:-reports/ai/context/latest.raw}"
OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"
mkdir -p "${OUTPUT_DIR}"

collect_section() {
  local title="$1"
  shift || true
  {
    echo "## ${title}"
    if "$@"; then
      :
    else
      status=$?
      echo "command failed with exit code ${status}"
    fi
    echo
  } >>"${OUTPUT_PATH}"
}

: >"${OUTPUT_PATH}"
echo "# RALF advisory context" >>"${OUTPUT_PATH}"
date -Iseconds >>"${OUTPUT_PATH}"
echo >>"${OUTPUT_PATH}"

collect_section "pvecm status" bash -c 'command -v pvecm >/dev/null 2>&1 && pvecm status || { echo "pvecm unavailable"; true; }'
collect_section "pvesh storage" bash -c 'command -v pvesh >/dev/null 2>&1 && pvesh get /storage --output-format json || { echo "pvesh storage unavailable"; true; }'
collect_section "pvesh nodes" bash -c 'command -v pvesh >/dev/null 2>&1 && pvesh get /nodes --output-format json || { echo "pvesh nodes unavailable"; true; }'
collect_section "zpool status" bash -c 'command -v zpool >/dev/null 2>&1 && zpool status || { echo "zpool unavailable"; true; }'
collect_section "ansible-lint" bash -c 'command -v ansible-lint >/dev/null 2>&1 && ansible-lint ansible/playbooks || { echo "ansible-lint unavailable"; true; }'

printf 'context written to %s\n' "${OUTPUT_PATH}"
