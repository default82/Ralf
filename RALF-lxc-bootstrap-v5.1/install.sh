#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="/root/ralf/logs"
STATE_DIR="/root/ralf/state"
PLAN_FILE="/root/ralf/plan.json"
INVENTORY_FILE="/root/ralf/inventory.json"
RESUME_FLAG="${STATE_DIR}/resume-phase2"
PVE_FLAG="${STATE_DIR}/pve-installed"
PHASE2_FLAG="${STATE_DIR}/phase2-complete"

mkdir -p "$LOG_DIR" "$STATE_DIR" /root/ralf/secrets
cp -f "$BASE_DIR/install.sh" /root/ralf/install.sh
chmod +x /root/ralf/install.sh
LOG_FILE="${LOG_DIR}/install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "[INFO] RALF LXC Bootstrap v5.1 gestartet am $(date)"

if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Bitte als root ausführen." >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || {
  echo "[ERROR] jq wird benötigt. Bitte laut README installieren." >&2
  exit 1
}

command -v whiptail >/dev/null 2>&1 || {
  echo "[ERROR] whiptail wird benötigt. Bitte laut README installieren." >&2
  exit 1
}

is_pve() {
  [[ -d /etc/pve && -f /usr/bin/pveversion ]]
}

current_phase() {
  if ! is_pve; then
    echo "phase1"
  else
    if [[ -f "$PHASE2_FLAG" ]]; then
      echo "done"
    else
      echo "phase2"
    fi
  fi
}

phase="$(current_phase)"

echo "[INFO] Aktuelle Phase: ${phase}"

if [[ "$phase" == "phase1" ]]; then
  echo "[INFO] Proxmox VE wird installiert."
  "$BASE_DIR/scripts/pve_install.sh"
  touch "$PVE_FLAG"
  echo "[INFO] Phase 1 abgeschlossen. Ein Reboot wird empfohlen/ausgeführt."
  exit 0
fi

if [[ "$phase" == "done" ]]; then
  echo "[INFO] Phase 2 bereits abgeschlossen. Vorgang beendet."
  exit 0
fi

# Phase 2

echo "[INFO] Phase 2 initialisiert."

echo "[INFO] Starte Planer."
if [[ ! -f "$PLAN_FILE" ]]; then
  cp -f "$BASE_DIR/config/plan.json" "$PLAN_FILE"
fi
"$BASE_DIR/scripts/plan_tui.sh" "$PLAN_FILE"

echo "[INFO] Ausgeführter Plan:"
cat "$PLAN_FILE"

echo "[INFO] Provisioniere Container über PVE-Provider."
"$BASE_DIR/providers/pve_provider.sh" "$PLAN_FILE" "$INVENTORY_FILE"

echo "[INFO] Installiere Dienste in Containern."
"$BASE_DIR/scripts/install_services.sh" "$PLAN_FILE" "$INVENTORY_FILE"

echo "[INFO] Caddy Edge-Proxy konfigurieren."
"$BASE_DIR/scripts/setup_edge_caddy.sh" "$PLAN_FILE" "$INVENTORY_FILE"

echo "[INFO] Omada-Integration (optional)."
"$BASE_DIR/scripts/omada_integrate.sh" "$PLAN_FILE" "$INVENTORY_FILE"

touch "$PHASE2_FLAG"
rm -f "$RESUME_FLAG"

echo "[INFO] Phase 2 abgeschlossen. Details siehe /root/ralf/links.txt."
