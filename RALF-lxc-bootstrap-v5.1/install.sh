#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

require_root(){ [[ $EUID -eq 0 ]] || { echo "Bitte als root (sudo -i) ausführen."; exit 1; }; }
is_pve(){ command -v pveversion >/dev/null 2>&1; }
is_debian(){ [[ -f /etc/debian_version ]]; }
pkg(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
set_hostname(){
  local t
  t=$(config_get '.hostname')
  hostnamectl set-hostname "$t"
  grep -q "$t" /etc/hosts || echo "127.0.1.1 $t" >> /etc/hosts
}
set_hostname(){ local t="pve-du-00"; hostnamectl set-hostname "$t"; grep -q "$t" /etc/hosts || echo "127.0.1.1 $t" >> /etc/hosts; }

phase2_pve(){
  bash scripts/plan_tui.sh
  bash providers/pve_provider.sh
  bash scripts/install_services.sh
  bash scripts/setup_edge_caddy.sh
  bash scripts/omada_integrate.sh || true
  local plan_path links_path
  plan_path=$(config_get '.plan_path')
  links_path=$(config_get '.links_path')
  whiptail --title "RALF v5.1" --msgbox "Fertig. Plan: ${plan_path}\nLinks: ${links_path}" 10 70
  whiptail --title "RALF v5.1" --msgbox "Fertig. Plan: /root/ralf/plan.json\nLinks: /root/ralf/links.txt" 10 70
}

main(){
  require_root
  pkg whiptail curl jq lshw pciutils ca-certificates
  set_hostname
  if is_pve; then phase2_pve; exit 0; fi
  if is_debian; then bash scripts/pve_install.sh; echo "[i] Bitte reboot."; exit 0; fi
  echo "Weder Debian noch Proxmox erkannt."; exit 1
}
main "$@"
