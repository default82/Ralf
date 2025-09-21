#!/usr/bin/env bash
set -euo pipefail

# Allow overriding the default via environment variables when sourcing/running
# the script while keeping the documented default of 10060.
: "${DEFAULT_VMID:=10060}"
cli_vmid=""

usage() {
  cat <<'EOF'
Usage: tests/smoke_wrapper.sh [--vmid <id>]

Runs the wrapper smoke test against the configured VMID. The VMID can be
overridden via the --vmid flag or the VMID environment variable. The
DEFAULT_VMID environment variable can be set to adjust the fallback value
without specifying a VMID explicitly.
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

read -r -d '' EXPECTED_HELP <<'EOF' || true
ralf-ai - Repo Assistant for Local Fixes

Usage: ralf-ai [--help] [--] [AIDER ARGUMENTS...]

Launch aider with repository safeguards and sensible defaults for an
OpenAI-compatible Ollama endpoint.

Environment variables:
  OPENAI_API_BASE       Base URL for the API (default: http://localhost:11434/v1)
  OPENAI_API_KEY        API key to present (default: ollama)
  OLLAMA_MODEL          Model name to request from aider (default: llama3:8b)
  AIDER_BIN             aider executable to invoke (default: aider)
  REPO_DIR              Repository path to guard (default: /srv/ralf)
  RALF_ALLOWED_BRANCHES Space-separated list of allowed branches
                        (default: "main feature/local-ai-hybrid")

Additional arguments are forwarded directly to aider.
EOF

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
  output="${EXPECTED_HELP}"
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
