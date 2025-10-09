#!/usr/bin/env bash
set -euo pipefail

FLAG="/root/ralf/state/resume-phase2"
INSTALLER="/root/ralf/install.sh"
LOG="/root/ralf/logs/resume.log"
mkdir -p /root/ralf/logs
exec >>"$LOG" 2>&1

echo "[resume] Trigger $(date)"

if [[ ! -f "$FLAG" ]]; then
  echo "[resume] Kein Resume-Flag gesetzt"
  exit 0
fi

if [[ ! -x "$INSTALLER" ]]; then
  echo "[resume][ERROR] Installer nicht ausführbar: $INSTALLER" >&2
  exit 1
fi

echo "[resume] Starte Installationsskript"
exec "$INSTALLER"
