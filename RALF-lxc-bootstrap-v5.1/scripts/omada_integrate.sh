#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE=${1:-/root/ralf/plan.json}
INVENTORY_FILE=${2:-/root/ralf/inventory.json}
LOG_DIR="/root/ralf/logs"
LOG_FILE="${LOG_DIR}/omada.log"
OUTPUT_FILE="/root/ralf/omada_integration.txt"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[omada] Start $(date)"

if [[ ! -f "$PLAN_FILE" || ! -f "$INVENTORY_FILE" ]]; then
  echo "[omada][ERROR] Plan oder Inventar fehlt" >&2
  exit 1
fi

ENABLED=$(jq -r '.omada.enabled' "$PLAN_FILE")
if [[ "$ENABLED" != "true" ]]; then
  echo "[omada] Omada Integration deaktiviert"
  echo "Omada Integration deaktiviert" > "$OUTPUT_FILE"
  exit 0
fi

CONTROLLER=$(jq -r '.omada.controller_url' "$PLAN_FILE")
SITE=$(jq -r '.omada.site' "$PLAN_FILE")
USER=$(jq -r '.omada.username' "$PLAN_FILE")
PASS=$(jq -r '.omada.password' "$PLAN_FILE")
DISCOVERY_VLAN=$(jq -r '.pxe.discovery_vlan' "$PLAN_FILE")
EDGE_IP=$(jq -r '.containers[] | select(.name=="ralf-edge") | .ip' "$INVENTORY_FILE")
FOREMAN_IP=$(jq -r '.containers[] | select(.name=="ralf-foreman") | .ip' "$INVENTORY_FILE")
PXE_MODE=$(jq -r '.pxe.mode' "$PLAN_FILE")

cat > "$OUTPUT_FILE" <<TXT
Omada Integrationsleitfaden ($(date))
====================================
Controller: ${CONTROLLER}
Site: ${SITE}
Discovery VLAN: ${DISCOVERY_VLAN}

1. Melde dich im Omada Controller an (Benutzer: ${USER}).
2. Lege eine NAT-Regel für WAN → LAN an:
   * Ports 80 und 443 auf ${EDGE_IP} weiterleiten.
3. Aktiviere DHCP-Relay oder Option 66/67 für VLAN ${DISCOVERY_VLAN}:
   * DHCP Relay Ziel: ${FOREMAN_IP}
   * Option 66: http://${FOREMAN_IP}:8000
   * Option 67: pxelinux.0 (bei TFTP) / http://${FOREMAN_IP}:8000/boot/ (HTTPBoot)
4. Stelle sicher, dass Firewall-Regeln Traffic zu ${EDGE_IP} und ${FOREMAN_IP} zulassen.
5. Prüfe nach Deployment die PXE-Discovery entsprechend Modus (${PXE_MODE}).

Best-Effort API Stub
--------------------
TXT

if [[ -n "$CONTROLLER" && "$CONTROLLER" != "null" ]]; then
  echo "[omada] Versuch API-Login (Best Effort)"
  RESPONSE=$(curl -sk --max-time 5 -X POST "${CONTROLLER}/api/v2/login" -H 'Content-Type: application/json' -d "{\"username\":\"${USER}\",\"password\":\"${PASS}\"}" || true)
  echo "API Login Response (gekürzt): ${RESPONSE:0:200}" >> "$OUTPUT_FILE"
else
  echo "Kein Controller URL hinterlegt" >> "$OUTPUT_FILE"
fi

echo "[omada] Hinweise nach ${OUTPUT_FILE} geschrieben"
