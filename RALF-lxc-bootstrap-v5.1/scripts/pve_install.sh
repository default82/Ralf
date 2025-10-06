#!/usr/bin/env bash
set -euo pipefail
require_root(){ [[ $EUID -eq 0 ]] || { echo "Bitte als root (sudo -i) ausführen."; exit 1; }; }
pkg(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
set_hostname(){ local t="pve-du-00"; hostnamectl set-hostname "$t"; grep -q "$t" /etc/hosts || echo "127.0.1.1 $t" >> /etc/hosts; }
default_if(){ ip route | awk '/default/ {print $5; exit}'; }
configure_vmbr0(){
  local iface="$(default_if)"; local ipaddr=$(ip -4 addr show dev "$iface" | awk '/inet /{print $2; exit}'); local gw=$(ip route | awk '/default/ {print $3; exit}')
  cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) || true
  cat >/etc/network/interfaces <<EOF_NET
auto lo
iface lo inet loopback

auto $iface
iface $iface inet manual

auto vmbr0
iface vmbr0 inet static
    address ${ipaddr}
    gateway ${gw}
    bridge-ports $iface
    bridge-stp off
    bridge-fd 0
EOF_NET
}
install_pve(){
  pkg curl gnupg
  echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
  curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi
  rm -f /etc/apt/sources.list.d/pve-enterprise.list || true
  apt-get -y full-upgrade
  touch /root/.ralf_resume_needed
  echo "[*] Proxmox VE installiert. Reboot nötig."
}
register_resume(){
  install -d -m 0755 /root/RALF-lxc-bootstrap-v5.1/scripts
  cp "$(dirname "$0")/resume.sh" /root/RALF-lxc-bootstrap-v5.1/scripts/resume.sh
  cp "$(dirname "$0")/resume.service" /etc/systemd/system/ralf-bootstrap-resume.service
  systemctl daemon-reload
  systemctl enable ralf-bootstrap-resume.service
}
main(){ require_root; set_hostname; install_pve; configure_vmbr0; register_resume; echo "reboot"; }
main "$@"
