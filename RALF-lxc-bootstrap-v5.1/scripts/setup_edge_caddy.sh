#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE=${1:-/root/ralf/plan.json}
INVENTORY_FILE=${2:-/root/ralf/inventory.json}
LOG_DIR="/root/ralf/logs"
LOG_FILE="${LOG_DIR}/edge.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[edge] Start $(date)"

for file in "$PLAN_FILE" "$INVENTORY_FILE"; do
  if [[ ! -f "$file" ]]; then
    echo "[edge][ERROR] Datei fehlt: $file" >&2
    exit 1
  fi
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[edge][ERROR] Kommando $1 fehlt" >&2
    exit 1
  }
}

for bin in jq pct; do
  require_cmd "$bin"
done

EDGE_CTI=$(jq -r '.containers[] | select(.name=="ralf-edge") | .ctid' "$INVENTORY_FILE")
if [[ -z "$EDGE_CTI" || "$EDGE_CTI" == "null" ]]; then
  echo "[edge][ERROR] CTID für ralf-edge nicht gefunden" >&2
  exit 1
fi

pct_exec() {
  pct exec "$EDGE_CTI" -- bash -lc "$*"
}

pct_exec "set -e; apt-get update; apt-get install -y debian-keyring debian-archive-keyring curl"
pct_exec "set -e; if ! test -f /etc/apt/trusted.gpg.d/caddy.gpg; then curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /etc/apt/trusted.gpg.d/caddy.gpg; fi"
pct_exec "set -e; echo 'deb [signed-by=/etc/apt/trusted.gpg.d/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main' >/etc/apt/sources.list.d/caddy.list"
pct_exec "set -e; apt-get update; apt-get install -y caddy jq"

HAS_PUBLIC=$(jq -r '.domain.has_public_domain' "$PLAN_FILE")
ACME_EMAIL=$(jq -r '.domain.acme_email' "$PLAN_FILE")

declare -A PORTS
PORTS[ralf-gitea]=3000
PORTS[ralf-netbox]=80
PORTS[ralf-n8n]=5678
PORTS[ralf-matrix]=8008
PORTS[ralf-secrets]=8080
PORTS[ralf-foreman]=443
PORTS[ralf-ki]=11434

CADDY_CFG=""

while read -r row; do
  name=$(echo "$row" | jq -r '.name')
  [[ "$name" == "ralf-edge" ]] && continue
  ip=$(echo "$row" | jq -r '.ip')
  fqdn=$(echo "$row" | jq -r '.fqdn')
  exposure=$(echo "$row" | jq -r '.exposure')
  port=${PORTS[$name]:-80}
  tls_block="tls internal"
  if [[ "$exposure" == "public" && "$HAS_PUBLIC" == "true" ]]; then
    tls_block="tls ${ACME_EMAIL}"
  fi
  if [[ -n "$CADDY_CFG" ]]; then
    CADDY_CFG+=$'\n'
  fi
  entry=$(cat <<EOF
${fqdn} {
    ${tls_block}
    encode gzip
    reverse_proxy ${ip}:${port}
}
EOF
)
  CADDY_CFG+="$entry"
done < <(jq -c '.containers[]' "$INVENTORY_FILE")

TMP_CADDY=$(mktemp)
echo "$CADDY_CFG" > "$TMP_CADDY"
pct push "$EDGE_CTI" "$TMP_CADDY" /etc/caddy/Caddyfile
rm -f "$TMP_CADDY"

pct_exec "caddy fmt --overwrite /etc/caddy/Caddyfile"
pct_exec "systemctl enable --now caddy"
pct_exec "systemctl reload caddy"

echo "[edge] Fertig"
