#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="/root/ralf/state"
mkdir -p "$STATE_DIR"

if [[ -d /etc/pve ]]; then
  echo "[pve_install] Proxmox bereits installiert"
  exit 0
fi

echo "[pve_install] Phase 1: Debian → Proxmox"

HOSTNAME_TARGET="pve-du-00"
SITE_CODE="DU"

current_if=$(ip -4 route ls default | awk '{print $5}' | head -n1)
current_ip=$(ip -4 addr show dev "$current_if" | awk '/inet / {print $2; exit}')
current_gw=$(ip route | awk '/default/ {print $3; exit}')

if [[ -z "$current_if" || -z "$current_ip" || -z "$current_gw" ]]; then
  echo "[pve_install][ERROR] Konnte aktuelle Netzwerkkonfiguration nicht bestimmen" >&2
  exit 1
fi

echo "[pve_install] Verwende Interface $current_if mit IP $current_ip und Gateway $current_gw"

hostnamectl set-hostname "$HOSTNAME_TARGET"
echo "$HOSTNAME_TARGET" > /etc/hostname
echo "127.0.1.1 ${HOSTNAME_TARGET}.local ${HOSTNAME_TARGET}" >> /etc/hosts

echo "[pve_install] Füge Proxmox Repository hinzu"
apt-get update
apt-get install -y curl gnupg lsb-release
wget -qO /etc/apt/trusted.gpg.d/proxmox-release.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
apt-get update

apt-get install -y proxmox-ve postfix open-iscsi --install-recommends

systemctl disable --now postfix || true

cat >/etc/apt/sources.list.d/pve-enterprise.list <<'LIST'
# Disabled enterprise repository
# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise
LIST

cat >/etc/network/interfaces <<EOF_NET
auto lo
iface lo inet loopback

auto ${current_if}
iface ${current_if} inet manual

allow-hotplug vmbr0
iface vmbr0 inet static
    address ${current_ip}
    gateway ${current_gw}
    bridge-ports ${current_if}
    bridge-stp off
    bridge-fd 0
EOF_NET

systemctl restart networking || true

echo "[pve_install] Installiere Resume-Service"
install -m 0755 "$BASE_DIR/scripts/resume.sh" /usr/local/sbin/ralf-resume.sh
install -m 0644 "$BASE_DIR/scripts/resume.service" /etc/systemd/system/ralf-resume.service
systemctl daemon-reload
systemctl enable ralf-resume.service

touch "$STATE_DIR/resume-phase2"

echo "[pve_install] Installation abgeschlossen. Bitte Reboot durchführen."
