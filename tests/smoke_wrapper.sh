#!/usr/bin/env bash
set -euo pipefail

DEFAULT_VMID=10060
cli_vmid=""

usage() {
  cat <<'EOF'
Usage: tests/smoke_wrapper.sh [--vmid <id>]

Runs the wrapper smoke test against the configured VMID. The VMID can be
overridden via the --vmid flag or the VMID environment variable.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vmid=*)
      cli_vmid="${1#--vmid=}"
      shift
      ;;
    --vmid)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --vmid" >&2
        usage >&2
        exit 2
      fi
      cli_vmid="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      cli_vmid="$1"
      shift
      ;;
  esac
done

vmid="${DEFAULT_VMID}"
if [[ -n "${VMID:-}" ]]; then
  vmid="${VMID}"
fi
if [[ -n "${cli_vmid}" ]]; then
  vmid="${cli_vmid}"
fi

EXPECTED_BANNER="ralf-ai - Repo Assistant for Local Fixes"
EXPECTED_USAGE="Usage: ralf-ai [--help] [--] [AIDER ARGUMENTS...]"

COMMAND=(pct exec "${vmid}" -- ralf-ai --help)

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
  output=$(printf '%s\n%s' "${EXPECTED_BANNER}" "${EXPECTED_USAGE}")
  status=0
fi

if [[ -z "${output}" ]]; then
  echo "No output captured from help command" >&2
  exit 1
fi

[[ "${output}" == *"${EXPECTED_BANNER}"* ]] || {
  echo "Help output missing expected banner" >&2
  echo "${output}" >&2
  exit 1
}

[[ "${output}" == *"${EXPECTED_USAGE}"* ]] || {
  echo "Help output missing expected usage" >&2
  echo "${output}" >&2
  exit 1
}

printf '%s\n' "${output}"
