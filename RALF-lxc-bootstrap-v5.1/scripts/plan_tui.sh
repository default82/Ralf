#!/usr/bin/env bash
set -euo pipefail

PLAN_DEF="config/plan.json"
OUTDIR="/root/ralf"
OUTPLAN="${OUTDIR}/plan.json"

require_root(){ [[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen (sudo -i)."; exit 1; }; }
pkg(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }

load_plan(){ mkdir -p "$OUTDIR"; if [[ -f "$OUTPLAN" ]]; then cp "$OUTPLAN" /tmp/plan.json; else cp "$PLAN_DEF" /tmp/plan.json; fi; }
save_plan(){ cp /tmp/plan.json "$OUTPLAN"; echo "[*] Plan gespeichert: $OUTPLAN"; }

tui_addressing(){
  local current=$(jq -r '.addressing' /tmp/plan.json)
  local addr=$(whiptail --title "Adressierung" --radiolist "Adressierung der LXCs:" 14 72 2 \
    "dhcp"   "Sicherer Start (empfohlen)" $( [[ "$current" == "dhcp" ]] && echo ON || echo OFF ) \
    "static" "Pro Kategorie /24 (192.168.<cat>.<host>)" $( [[ "$current" == "static" ]] && echo ON || echo OFF ) \
    3>&1 1>&2 2>&3) || addr="$current"
  jq --arg a "$addr" '.addressing=$a' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  if [[ "$addr" == "static" ]]; then
    local base=$(jq -r '.ip_base' /tmp/plan.json)
    base=$(whiptail --inputbox "IP-Basis (CIDR /16):" 10 60 "${base}" 3>&1 1>&2 2>&3) || true
    jq --arg b "$base" '.ip_base=$b' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
    local gw=$(jq -r '.gateway_octet' /tmp/plan.json)
    gw=$(whiptail --inputbox "Gateway .<octet> (z.B. 1 -> 192.168.<cat>.1)" 10 60 "${gw}" 3>&1 1>&2 2>&3) || true
    jq --argjson g "${gw:-1}" '.gateway_octet=$g' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  fi
}

tui_domain(){
  local has=$(jq -r '.domain.has_public_domain' /tmp/plan.json)
  local yn=$(whiptail --title "Domain" --yesno "Hast du eine öffentliche Domain, die auf deinen Anschluss geroutet werden kann?" 10 70 && echo yes || echo no)
  [[ "$yn" == "yes" ]] && has=true || has=false
  jq --argjson v "$has" '.domain.has_public_domain=$v' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  local base=$(jq -r '.domain.base_domain' /tmp/plan.json)
  base=$(whiptail --inputbox "Basis-Domain (z.B. homelab.example.com):" 10 70 "$base" 3>&1 1>&2 2>&3) || true
  jq --arg b "$base" '.domain.base_domain=$b' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  local mail=$(jq -r '.domain.acme_email' /tmp/plan.json)
  mail=$(whiptail --inputbox "ACME E-Mail (Let's Encrypt):" 10 70 "$mail" 3>&1 1>&2 2>&3) || true
  jq --arg m "$mail" '.domain.acme_email=$m' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
}

tui_services(){
  local keys=$(jq -r '.services | keys[]' /tmp/plan.json)
  for svc in $keys; do
    local exp=$(jq -r ".services[\"$svc\"].exposure" /tmp/plan.json)
    local sel=$(whiptail --title "Exposure: $svc" --radiolist "Öffentlich erreichbar?" 12 70 2 \
      "public" "Ja, über ralf-edge + TLS" $( [[ "$exp" == "public" ]] && echo ON || echo OFF ) \
      "local"  "Nur intern/LAN"           $( [[ "$exp" == "local" ]] && echo ON || echo OFF ) \
      3>&1 1>&2 2>&3) || sel="$exp"
    jq --arg s "$svc" --arg e "$sel" '.services[$s].exposure=$e' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json

    local base=$(jq -r '.domain.base_domain' /tmp/plan.json)
    local def_fqdn=$(jq -r ".services[\"$svc\"].fqdn" /tmp/plan.json)
    [[ -z "$def_fqdn" || "$def_fqdn" == "null" ]] && def_fqdn="${svc}.${base}"
    local fqdn=$(whiptail --inputbox "FQDN für $svc (bei public):" 10 70 "$def_fqdn" 3>&1 1>&2 2>&3) || fqdn="$def_fqdn"
    jq --arg s "$svc" --arg f "$fqdn" '.services[$s].fqdn=$f' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  done
}

tui_pxe(){
  local mode=$(jq -r '.pxe.mode' /tmp/plan.json)
  local sel=$(whiptail --title "PXE/Discovery" --radiolist "PXE-Modus wählen:" 14 80 3 \
    "disabled"      "Kein PXE/Discovery"   $( [[ "$mode" == "disabled" ]] && echo ON || echo OFF ) \
    "router_relay"  "Router DHCP + Relay/Optionen → Foreman (empfohlen)" $( [[ "$mode" == "router_relay" ]] && echo ON || echo OFF ) \
    "foreman_dhcp"  "Foreman DHCP/TFTP übernimmt (riskant)" $( [[ "$mode" == "foreman_dhcp" ]] && echo ON || echo OFF ) \
    3>&1 1>&2 2>&3) || sel="$mode"
  jq --arg m "$sel" '.pxe.mode=$m' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  local dv=$(jq -r '.pxe.discovery_vlan' /tmp/plan.json)
  dv=$(whiptail --inputbox "Discovery VLAN (z.B. 250):" 10 60 "$dv" 3>&1 1>&2 2>&3) || true
  jq --argjson v ${dv:-250} '.pxe.discovery_vlan=$v' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
}

summary(){
  local addr=$(jq -r '.addressing' /tmp/plan.json)
  local dom=$(jq -r '.domain.base_domain' /tmp/plan.json)
  local mode=$(jq -r '.pxe.mode' /tmp/plan.json)
  local tbl=$(jq -r '.services | to_entries[] | "\(.key)\tcat:\(.value.category)\toct:\(.value.host_octet)\tctid:\(.value.ctid // "auto")\texp:\(.value.exposure)\tfqdn:\(.value.fqdn)"' /tmp/plan.json)
  whiptail --title "Zusammenfassung" --msgbox "Adressierung: ${addr}\nDomain: ${dom}\nPXE: ${mode}\n\n${tbl}" 20 90
}

compute_ctids(){
  keys=$(jq -r '.services | keys[]' /tmp/plan.json)
  for svc in $keys; do
    cat=$(jq -r ".services[\"$svc\"].category" /tmp/plan.json)
    host=$(jq -r ".services[\"$svc\"].host_octet" /tmp/plan.json)
    if [[ "$host" -lt 100 ]]; then ctid=$((cat*100 + host)); else ctid=$((cat*1000 + host)); fi
    jq --arg s "$svc" --argjson id $ctid '.services[$s].ctid=$id' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  done
}

main(){
  require_root
  load_plan
  pkg jq whiptail
  tui_addressing
  tui_domain
  tui_services
  tui_pxe
  compute_ctids
  summary
  save_plan
}
main "$@"
