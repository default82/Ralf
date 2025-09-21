#!/usr/bin/env bash
set -euo pipefail

# Fetches a secret from Vaultwarden using the Bitwarden CLI (bw).
#
# Required environment variables:
#   BW_CLIENTID / BW_CLIENTSECRET (for API key login) or BW_SESSION (for unlocked session)
#   VAULTWARDEN_URL – Base URL of the Vaultwarden instance
#   VAULTWARDEN_ITEM – Item name or UUID to retrieve
#   VAULTWARDEN_FIELD – Field inside the item (e.g., password, notes, custom field)
#
# Optional:
#   BW_PASSWORD – master password used with `bw unlock`
#
# Usage:
#   VAULTWARDEN_URL=https://vaultwarden.homelab.lan \
#   VAULTWARDEN_ITEM="n8n-matrix-token" \
#   VAULTWARDEN_FIELD=password \
#   ./fetch_secret.sh

if ! command -v bw >/dev/null 2>&1; then
  echo "bw CLI not found. Install Bitwarden CLI to fetch secrets." >&2
  exit 1
fi

VAULTWARDEN_URL=${VAULTWARDEN_URL:-}
VAULTWARDEN_ITEM=${VAULTWARDEN_ITEM:-}
VAULTWARDEN_FIELD=${VAULTWARDEN_FIELD:-password}

if [[ -z "${VAULTWARDEN_URL}" || -z "${VAULTWARDEN_ITEM}" ]]; then
  echo "VAULTWARDEN_URL and VAULTWARDEN_ITEM must be set." >&2
  exit 2
fi

export BW_SERVER="${VAULTWARDEN_URL}"

if [[ -z "${BW_SESSION:-}" ]]; then
  if [[ -z "${BW_CLIENTID:-}" || -z "${BW_CLIENTSECRET:-}" ]]; then
    echo "Provide either BW_SESSION or BW_CLIENTID/BW_CLIENTSECRET for authentication." >&2
    exit 3
  fi

  echo "Authenticating against Vaultwarden API ..." >&2
  bw login --apikey >/dev/null

  if [[ -n "${BW_PASSWORD:-}" ]]; then
    echo "Unlocking vault using provided master password ..." >&2
    export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
  else
    echo "Unlocking vault interactively ..." >&2
    export BW_SESSION=$(bw unlock --raw)
  fi
fi

secret_json=$(bw get item --session "${BW_SESSION}" "${VAULTWARDEN_ITEM}")

if [[ -z "${secret_json}" ]]; then
  echo "Failed to retrieve item ${VAULTWARDEN_ITEM}" >&2
  exit 4
fi

jq -r --arg field "${VAULTWARDEN_FIELD}" '
  if .fields then
    (.fields[] | select(.name == $field) | .value) //
    (if $field == "password" then .login.password else empty end)
  else
    (if $field == "password" then .login.password else .notes end)
  end
' <<<"${secret_json}"
