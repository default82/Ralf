#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

CONFIG_TMP="$(mktemp)"
PLAN_TMP="/tmp/plan.json"
STATE_DIR=""
PLAN_TEMPLATE=""
PLAN_PATH=""
INVENTORY_PATH=""
SECRETS_DIR=""
LINKS_PATH=""
PLAN_DEF="config/plan.json"
OUTDIR="/root/ralf"
OUTPLAN="${OUTDIR}/plan.json"

require_root(){ [[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen (sudo -i)."; exit 1; }; }
pkg(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }

cleanup(){ rm -f "$CONFIG_TMP" "$PLAN_TMP"; }

load_config(){
  if [[ -f "$CONFIG_PATH" ]]; then
    cp "$CONFIG_PATH" "$CONFIG_TMP"
  else
    cp "$DEFAULT_CONFIG" "$CONFIG_TMP"
  fi
}

update_config_paths(){
  local dir
  dir=$(jq -r '.state_dir' "$CONFIG_TMP")
  jq --arg dir "$dir" '
    .plan_path = ($dir + "/plan.json") |
    .inventory_path = ($dir + "/inventory.json") |
    .secrets_dir = ($dir + "/secrets") |
    .links_path = ($dir + "/links.txt") |
    .omada_path = ($dir + "/omada.json") |
    .ki_choice_path = ($dir + "/ki_choice.txt")
  ' "$CONFIG_TMP" > "${CONFIG_TMP}.new" && mv "${CONFIG_TMP}.new" "$CONFIG_TMP"
}

config_prompt_state_dir(){
  local current newdir
  current=$(jq -r '.state_dir' "$CONFIG_TMP")
  newdir=$(whiptail --inputbox "State-Verzeichnis für RALF (absolute Pfad):" 10 70 "$current" 3>&1 1>&2 2>&3) || newdir="$current"
  [[ -z "$newdir" ]] && newdir="$current"
  jq --arg dir "$newdir" '.state_dir=$dir' "$CONFIG_TMP" > "${CONFIG_TMP}.new" && mv "${CONFIG_TMP}.new" "$CONFIG_TMP"
  update_config_paths
}

config_prompt_pve(){
  local storage template
  storage=$(jq -r '.pve.storage' "$CONFIG_TMP")
  storage=$(whiptail --inputbox "Proxmox Storage (für Templates & CTs):" 10 70 "$storage" 3>&1 1>&2 2>&3) || storage=$(jq -r '.pve.storage' "$CONFIG_TMP")
  jq --arg val "$storage" '.pve.storage=$val' "$CONFIG_TMP" > "${CONFIG_TMP}.new" && mv "${CONFIG_TMP}.new" "$CONFIG_TMP"

  template=$(jq -r '.pve.template_pattern' "$CONFIG_TMP")
  template=$(whiptail --inputbox "Template-Suchmuster (pveam available):" 10 70 "$template" 3>&1 1>&2 2>&3) || template=$(jq -r '.pve.template_pattern' "$CONFIG_TMP")
  jq --arg val "$template" '.pve.template_pattern=$val' "$CONFIG_TMP" > "${CONFIG_TMP}.new" && mv "${CONFIG_TMP}.new" "$CONFIG_TMP"
}

config_prompt_resources(){
  local services service mem cores
  services=$(jq -r '.resources | keys[]' "$CONFIG_TMP")
  for service in $services; do
    mem=$(jq -r ".resources[\"$service\"].memory" "$CONFIG_TMP")
    cores=$(jq -r ".resources[\"$service\"].cores" "$CONFIG_TMP")
    mem=$(whiptail --inputbox "RAM für ${service} (MB):" 10 70 "$mem" 3>&1 1>&2 2>&3) || mem=$(jq -r ".resources[\"$service\"].memory" "$CONFIG_TMP")
    cores=$(whiptail --inputbox "vCPU für ${service}:" 10 70 "$cores" 3>&1 1>&2 2>&3) || cores=$(jq -r ".resources[\"$service\"].cores" "$CONFIG_TMP")
    jq --arg svc "$service" --argjson mem "${mem:-0}" --argjson cores "${cores:-1}" '.resources[$svc].memory=$mem | .resources[$svc].cores=$cores' "$CONFIG_TMP" > "${CONFIG_TMP}.new" && mv "${CONFIG_TMP}.new" "$CONFIG_TMP"
  done
}

config_prompt_hostname(){
  local host
  host=$(jq -r '.hostname' "$CONFIG_TMP")
  host=$(whiptail --inputbox "Proxmox Hostname:" 10 70 "$host" 3>&1 1>&2 2>&3) || host=$(jq -r '.hostname' "$CONFIG_TMP")
  jq --arg h "$host" '.hostname=$h' "$CONFIG_TMP" > "${CONFIG_TMP}.new" && mv "${CONFIG_TMP}.new" "$CONFIG_TMP"
}

configure_settings(){
  if whiptail --title "RALF Konfiguration" --yesno "Globale Einstellungen prüfen/anpassen?" 10 70; then
    config_prompt_state_dir
    config_prompt_hostname
    config_prompt_pve
    config_prompt_resources
  fi
}

save_config(){
  local state_dir secrets_dir
  state_dir=$(jq -r '.state_dir' "$CONFIG_TMP")
  secrets_dir=$(jq -r '.secrets_dir' "$CONFIG_TMP")
  mkdir -p "$state_dir" "$secrets_dir"
  mkdir -p "$(dirname "$CONFIG_PATH")"
  cp "$CONFIG_TMP" "$CONFIG_PATH"
  CONFIG_FILE="$CONFIG_PATH"
  echo "[*] Konfiguration gespeichert: $CONFIG_PATH"
}

refresh_paths(){
  STATE_DIR=$(jq -r '.state_dir' "$CONFIG_FILE")
  PLAN_PATH=$(jq -r '.plan_path' "$CONFIG_FILE")
  PLAN_TEMPLATE=$(jq -r '.plan_template' "$CONFIG_FILE")
  INVENTORY_PATH=$(jq -r '.inventory_path' "$CONFIG_FILE")
  SECRETS_DIR=$(jq -r '.secrets_dir' "$CONFIG_FILE")
  LINKS_PATH=$(jq -r '.links_path' "$CONFIG_FILE")
  if [[ "$PLAN_TEMPLATE" != /* ]]; then
    PLAN_TEMPLATE="${PROJECT_ROOT}/${PLAN_TEMPLATE}"
  fi
}

load_plan(){
  mkdir -p "$STATE_DIR"
  if [[ -f "$PLAN_PATH" ]]; then
    cp "$PLAN_PATH" "$PLAN_TMP"
  else
    cp "$PLAN_TEMPLATE" "$PLAN_TMP"
  fi
}

save_plan(){
  cp "$PLAN_TMP" "$PLAN_PATH"
  echo "[*] Plan gespeichert: $PLAN_PATH"
}

tui_addressing(){
  local current=$(jq -r '.addressing' "$PLAN_TMP")
load_plan(){ mkdir -p "$OUTDIR"; if [[ -f "$OUTPLAN" ]]; then cp "$OUTPLAN" /tmp/plan.json; else cp "$PLAN_DEF" /tmp/plan.json; fi; }
save_plan(){ cp /tmp/plan.json "$OUTPLAN"; echo "[*] Plan gespeichert: $OUTPLAN"; }

tui_addressing(){
  local current=$(jq -r '.addressing' /tmp/plan.json)
  local addr=$(whiptail --title "Adressierung" --radiolist "Adressierung der LXCs:" 14 72 2 \
    "dhcp"   "Sicherer Start (empfohlen)" $( [[ "$current" == "dhcp" ]] && echo ON || echo OFF ) \
    "static" "Pro Kategorie /24 (192.168.<cat>.<host>)" $( [[ "$current" == "static" ]] && echo ON || echo OFF ) \
    3>&1 1>&2 2>&3) || addr="$current"
  jq --arg a "$addr" '.addressing=$a' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
  if [[ "$addr" == "static" ]]; then
    local base=$(jq -r '.ip_base' "$PLAN_TMP")
    base=$(whiptail --inputbox "IP-Basis (CIDR /16):" 10 60 "${base}" 3>&1 1>&2 2>&3) || true
    jq --arg b "$base" '.ip_base=$b' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
    local gw=$(jq -r '.gateway_octet' "$PLAN_TMP")
    gw=$(whiptail --inputbox "Gateway .<octet> (z.B. 1 -> 192.168.<cat>.1)" 10 60 "${gw}" 3>&1 1>&2 2>&3) || true
    jq --argjson g "${gw:-1}" '.gateway_octet=$g' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
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
  local has=$(jq -r '.domain.has_public_domain' "$PLAN_TMP")
  local yn=$(whiptail --title "Domain" --yesno "Hast du eine öffentliche Domain, die auf deinen Anschluss geroutet werden kann?" 10 70 && echo yes || echo no)
  [[ "$yn" == "yes" ]] && has=true || has=false
  jq --argjson v "$has" '.domain.has_public_domain=$v' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
  local base=$(jq -r '.domain.base_domain' "$PLAN_TMP")
  base=$(whiptail --inputbox "Basis-Domain (z.B. homelab.example.com):" 10 70 "$base" 3>&1 1>&2 2>&3) || true
  jq --arg b "$base" '.domain.base_domain=$b' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
  local mail=$(jq -r '.domain.acme_email' "$PLAN_TMP")
  mail=$(whiptail --inputbox "ACME E-Mail (Let's Encrypt):" 10 70 "$mail" 3>&1 1>&2 2>&3) || true
  jq --arg m "$mail" '.domain.acme_email=$m' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
}

tui_services(){
  local keys=$(jq -r '.services | keys[]' "$PLAN_TMP")
  for svc in $keys; do
    local exp=$(jq -r ".services[\"$svc\"].exposure" "$PLAN_TMP")
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
    jq --arg s "$svc" --arg e "$sel" '.services[$s].exposure=$e' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"

    local base=$(jq -r '.domain.base_domain' "$PLAN_TMP")
    local def_fqdn=$(jq -r ".services[\"$svc\"].fqdn" "$PLAN_TMP")
    [[ -z "$def_fqdn" || "$def_fqdn" == "null" ]] && def_fqdn="${svc}.${base}"
    local fqdn=$(whiptail --inputbox "FQDN für $svc (bei public):" 10 70 "$def_fqdn" 3>&1 1>&2 2>&3) || fqdn="$def_fqdn"
    jq --arg s "$svc" --arg f "$fqdn" '.services[$s].fqdn=$f' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
    jq --arg s "$svc" --arg e "$sel" '.services[$s].exposure=$e' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json

    local base=$(jq -r '.domain.base_domain' /tmp/plan.json)
    local def_fqdn=$(jq -r ".services[\"$svc\"].fqdn" /tmp/plan.json)
    [[ -z "$def_fqdn" || "$def_fqdn" == "null" ]] && def_fqdn="${svc}.${base}"
    local fqdn=$(whiptail --inputbox "FQDN für $svc (bei public):" 10 70 "$def_fqdn" 3>&1 1>&2 2>&3) || fqdn="$def_fqdn"
    jq --arg s "$svc" --arg f "$fqdn" '.services[$s].fqdn=$f' /tmp/plan.json > /tmp/plan.new && mv /tmp/plan.new /tmp/plan.json
  done
}

tui_pxe(){
  local mode=$(jq -r '.pxe.mode' "$PLAN_TMP")
  local mode=$(jq -r '.pxe.mode' /tmp/plan.json)
  local sel=$(whiptail --title "PXE/Discovery" --radiolist "PXE-Modus wählen:" 14 80 3 \
    "disabled"      "Kein PXE/Discovery"   $( [[ "$mode" == "disabled" ]] && echo ON || echo OFF ) \
    "router_relay"  "Router DHCP + Relay/Optionen → Foreman (empfohlen)" $( [[ "$mode" == "router_relay" ]] && echo ON || echo OFF ) \
    "foreman_dhcp"  "Foreman DHCP/TFTP übernimmt (riskant)" $( [[ "$mode" == "foreman_dhcp" ]] && echo ON || echo OFF ) \
    3>&1 1>&2 2>&3) || sel="$mode"
  jq --arg m "$sel" '.pxe.mode=$m' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
  local dv=$(jq -r '.pxe.discovery_vlan' "$PLAN_TMP")
  dv=$(whiptail --inputbox "Discovery VLAN (z.B. 250):" 10 60 "$dv" 3>&1 1>&2 2>&3) || true
  jq --argjson v ${dv:-250} '.pxe.discovery_vlan=$v' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
}

summary(){
  local addr dom mode storage state tbl
  addr=$(jq -r '.addressing' "$PLAN_TMP")
  dom=$(jq -r '.domain.base_domain' "$PLAN_TMP")
  mode=$(jq -r '.pxe.mode' "$PLAN_TMP")
  storage=$(jq -r '.pve.storage' "$CONFIG_FILE")
  state=$(jq -r '.state_dir' "$CONFIG_FILE")
  tbl=$(jq -r '.services | to_entries[] | "\(.key)\tcat:\(.value.category)\toct:\(.value.host_octet)\tctid:\(.value.ctid // "auto")\texp:\(.value.exposure)\tfqdn:\(.value.fqdn)"' "$PLAN_TMP")
  whiptail --title "Zusammenfassung" --msgbox "State: ${state}\nStorage: ${storage}\nAdressierung: ${addr}\nDomain: ${dom}\nPXE: ${mode}\n\n${tbl}" 20 90
}

compute_ctids(){
  keys=$(jq -r '.services | keys[]' "$PLAN_TMP")
  for svc in $keys; do
    cat=$(jq -r ".services[\"$svc\"].category" "$PLAN_TMP")
    host=$(jq -r ".services[\"$svc\"].host_octet" "$PLAN_TMP")
    if [[ "$host" -lt 100 ]]; then ctid=$((cat*100 + host)); else ctid=$((cat*1000 + host)); fi
    jq --arg s "$svc" --argjson id $ctid '.services[$s].ctid=$id' "$PLAN_TMP" > "${PLAN_TMP}.new" && mv "${PLAN_TMP}.new" "$PLAN_TMP"
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
  trap cleanup EXIT
  require_root
  pkg jq whiptail
  load_config
  configure_settings
  save_config
  refresh_paths
  load_plan
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
