#!/usr/bin/env bash
set -euo pipefail

# Simple smoke checks for the integration services introduced with n8n/Matrix.

N8N_BASE_URL=${N8N_BASE_URL:-http://n8n01:5678}
SYNAPSE_BASE_URL=${SYNAPSE_BASE_URL:-https://synapse01:8448}
ELEMENT_BASE_URL=${ELEMENT_BASE_URL:-https://elementweb01}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for smoke checks" >&2
  exit 1
fi

function curl_json() {
  local url=$1
  shift
  curl --fail --silent --show-error --location "$url" "$@"
}

echo "[n8n] Checking ${N8N_BASE_URL}/healthz" >&2
curl_json "${N8N_BASE_URL}/healthz" | jq '.' >/dev/null

echo "[synapse] Checking ${SYNAPSE_BASE_URL}/_matrix/federation/v1/version" >&2
curl_json "${SYNAPSE_BASE_URL}/_matrix/federation/v1/version" | jq '.' >/dev/null

echo "[element-web] Checking static bundle at ${ELEMENT_BASE_URL}" >&2
curl --fail --silent --show-error --location "${ELEMENT_BASE_URL}" >/dev/null

echo "All integration smoke checks passed." >&2
