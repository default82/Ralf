# R.A.L.F. – LXC Bootstrap **v5.1**

**Neu:** 
- **GPU-Profile**: NVIDIA/AMD/Intel (best effort) in der KI-Auswahl.
- **Caddy Edge (ralf-edge)**: Reverse Proxy in eigenem LXC, pro Dienst **public/local** steuerbar.
- **Domain/ACME**: Basis-Domain & E-Mail; Caddy versucht automatisch TLS (Let’s Encrypt).
- **PXE**: Foreman mit **HTTPBoot/TFTP**; Modus **Router-DHCP + Relay (empfohlen)** oder **Foreman-DHCP (Takeover)**.
- **Omada-Integration (optional)**: Controller-URL/Site/User/Pass → Portforward 80/443 zu `ralf-edge`, DHCP Relay/Optionen (best-effort API).

## Schnellstart
```bash
sudo -i
apt-get update -y && apt-get install -y whiptail curl jq lshw pciutils ca-certificates
unzip RALF-lxc-bootstrap-v5.1.zip
cd RALF-lxc-bootstrap-v5.1
bash ./install.sh
# (auf Debian) reboot → Planer → Provider → Dienste
```

---

### Datei: `config/plan.json` (Default-Plan, wird vom TUI überschrieben)
```json
{
  "site": "DU",
  "addressing": "dhcp",
  "ip_base": "192.168.0.0/16",
  "gateway_octet": 1,
  "domain": {
    "has_public_domain": false,
    "base_domain": "homelab.example.com",
    "acme_email": "admin@example.com"
  },
  "pxe": {
    "mode": "router_relay",
    "discovery_vlan": 250
  },
  "omada": {
    "enabled": false,
    "controller_url": "https://omada.local",
    "site": "Default",
    "username": "admin",
    "password": "changeme"
  },
  "categories": [
    {"code":10,"name":"Netzwerkdienste"},
    {"code":20,"name":"Datenbanken"},
    {"code":30,"name":"Backup & Sicherheit"},
    {"code":40,"name":"Web & Verwaltungsoberflächen"},
    {"code":50,"name":"Verzeichnisdienste & Authentifizierung"},
    {"code":60,"name":"Medienserver & Verwaltung"},
    {"code":70,"name":"Dokumenten- & Wissensmanagement"},
    {"code":80,"name":"Monitoring & Logging"},
    {"code":90,"name":"Künstliche Intelligenz & Datenverarbeitung"},
    {"code":100,"name":"Automatisierung"},
    {"code":110,"name":"Kommunikation und Steuerung"},
    {"code":120,"name":"Spiele"},
    {"code":200,"name":"funktionale VM"}
  ],
  "services": {
    "ralf-edge":   {"category":40,"host_octet":80,"tags":["role-edge","cat-40-web","site-DU","env-prod","stack-edge"],"exposure":"public","fqdn":"edge.homelab.example.com","ctid":4080},
    "ralf-ki":     {"category":90,"host_octet":10,"tags":["role-ralf-ki","cat-90-ai","site-DU","env-prod","stack-ai"],"exposure":"local","fqdn":"ai.homelab.example.com","ctid":9010},
    "ralf-gitea":  {"category":40,"host_octet":11,"tags":["role-gitea","cat-40-web","site-DU","env-prod","stack-web"],"exposure":"local","fqdn":"gitea.homelab.example.com","ctid":4011},
    "ralf-netbox": {"category":40,"host_octet":12,"tags":["role-netbox","cat-40-web","site-DU","env-prod","stack-web"],"exposure":"public","fqdn":"netbox.homelab.example.com","ctid":4012},
    "ralf-db":     {"category":20,"host_octet":3, "tags":["role-db","cat-20-db","site-DU","env-prod","stack-db"],"exposure":"local","fqdn":"db.homelab.example.com","ctid":2003},
    "ralf-n8n":    {"category":100,"host_octet":14,"tags":["role-n8n","cat-100-auto","site-DU","env-prod","stack-automation"],"exposure":"public","fqdn":"n8n.homelab.example.com","ctid":10014},
    "ralf-matrix": {"category":110,"host_octet":15,"tags":["role-matrix","cat-110-comm","site-DU","env-prod","stack-comm"],"exposure":"public","fqdn":"chat.homelab.example.com","ctid":11015},
    "ralf-secrets":{"category":30,"host_octet":16,"tags":["role-vaultwarden","cat-30-sec","site-DU","env-prod","stack-security"],"exposure":"local","fqdn":"vault.homelab.example.com","ctid":30016},
    "ralf-foreman":{"category":100,"host_octet":7, "tags":["role-foreman","cat-100-auto","site-DU","env-prod","stack-automation"],"exposure":"local","fqdn":"foreman.homelab.example.com","ctid":10007}
  }
}
```

Datei: install.sh
```bash
#!/usr/bin/env bash
set -euo pipefail
require_root(){ [[ $EUID -eq 0 ]] || { echo "Bitte als root (sudo -i) ausführen."; exit 1; }; }
is_pve(){ command -v pveversion >/dev/null 2>&1; }
is_debian(){ [[ -f /etc/debian_version ]]; }
pkg(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
set_hostname(){ local t="pve-du-00"; hostnamectl set-hostname "$t"; grep -q "$t" /etc/hosts || echo "127.0.1.1 $t" >> /etc/hosts; }

phase2_pve(){
  bash scripts/plan_tui.sh
  bash providers/pve_provider.sh
  bash scripts/install_services.sh
  bash scripts/setup_edge_caddy.sh
  bash scripts/omada_integrate.sh || true
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
```


Hinweise zur Nutzung

Erstlauf auf Debian: `bash ./install.sh` → PVE-Install, Reboot, dann TUI automatisch.

Plan anpassen: `bash scripts/plan_tui.sh` (CTIDs/IPs/Tags/Domain/Expose/PXE/Omada).

Erneut ausrollen: `bash providers/pve_provider.sh && bash scripts/install_services.sh && bash scripts/setup_edge_caddy.sh`.

Ergebnisse:

- Plan: `/root/ralf/plan.json`
- Inventar: `/root/ralf/inventory.json`
- DB-Secrets: `/root/ralf/secrets/db.env`
- Links: `/root/ralf/links.txt`
