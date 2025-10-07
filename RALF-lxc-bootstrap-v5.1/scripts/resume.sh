#!/usr/bin/env bash
set -euo pipefail
require_root(){ [[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen."; exit 1; }; }
pkg(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
phase2(){ cd /root/RALF-lxc-bootstrap-v5.1; bash scripts/plan_tui.sh; bash providers/pve_provider.sh; bash scripts/install_services.sh; bash scripts/setup_edge_caddy.sh; bash scripts/omada_integrate.sh || true; rm -f /root/.ralf_resume_needed; systemctl disable ralf-bootstrap-resume.service || true; echo "[OK] RALF v5.1 abgeschlossen."; }
main(){ require_root; if ! command -v pveversion >/dev/null 2>&1; then echo "PVE fehlt"; exit 1; fi; pkg whiptail jq curl lshw pciutils ca-certificates; phase2; }
main "$@"
