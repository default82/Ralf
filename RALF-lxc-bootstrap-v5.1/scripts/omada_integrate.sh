#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

PLAN=$(jq -r '.plan_path' "$CONFIG_FILE")
INV=$(jq -r '.inventory_path' "$CONFIG_FILE")
OMADA_JSON=$(jq -r '.omada_path' "$CONFIG_FILE")

mkdir -p "$(dirname "$OMADA_JSON")"

jq '.omada' "$PLAN" > "$OMADA_JSON"

enabled=$(jq -r '.enabled' "$OMADA_JSON")
[[ "$enabled" == "true" ]] || { echo "[i] Omada-Integration deaktiviert, überspringe."; exit 0; }

controller=$(jq -r '.controller_url' "$OMADA_JSON")
site=$(jq -r '.site' "$OMADA_JSON")
user=$(jq -r '.username' "$OMADA_JSON")
pass=$(jq -r '.password' "$OMADA_JSON")

EDGE_IP=$(jq -r '.["ralf-edge"].ip' "$INV")
FOREMAN_IP=$(jq -r '.["ralf-foreman"].ip' "$INV")
DISC_VLAN=$(jq -r '.pxe.discovery_vlan' "$PLAN")

echo "[*] Omada: Login/Config (best-effort) @ ${controller} site=${site}"
echo "[*] Portforward 80,443 -> ${EDGE_IP} (Bitte im Controller prüfen / freigeben)"
echo "[*] DHCP Option/Relay für VLAN ${DISC_VLAN} -> ${FOREMAN_IP} konfigurieren (Option 66/67 oder DHCP-Relay)."

exit 0
