#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

LOG_TAG=${LOG_TAG:-ralf-installer}
LOGGER_BIN=$(command -v logger || true)
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VARS_FILE="${PROJECT_ROOT}/infra/network/preflight.vars.source"
IP_SCHEMA_FILE="${PROJECT_ROOT}/infra/network/ip-schema.yml"
SUMMARY_FILE="${PROJECT_ROOT}/infra/network/installer-summary.txt"

log(){
  local level=$1; shift
  local message=$*
  [[ -n ${LOGGER_BIN:-} ]] && ${LOGGER_BIN} -t "${LOG_TAG}" "${level}: ${message}" || true
  printf '%s: %s\n' "${level}" "${message}"
}

UI_BIN=""
UI_MODE=""

init_ui(){
  if command -v whiptail >/dev/null 2>&1; then
    UI_BIN=$(command -v whiptail)
    UI_MODE="whiptail"
    return 0
  fi
  if command -v dialog >/dev/null 2>&1; then
    UI_BIN=$(command -v dialog)
    UI_MODE="dialog"
    return 0
  fi
  log "ERROR" "Weder whiptail noch dialog verfügbar. Bitte preflight.sh ausführen, um Abhängigkeiten zu installieren."
  exit 1
}

ui_msg(){
  local title=$1 text=$2
  if [[ ${UI_MODE} == "whiptail" ]]; then
    ${UI_BIN} --title "${title}" --msgbox "${text}" 12 70
  else
    ${UI_BIN} --title "${title}" --msgbox "${text}" 12 70
  fi
}

ui_yesno(){
  local title=$1 text=$2 default=${3:-Yes}
  local opts=("--title" "${title}" "--yesno" "${text}" 12 70)
  if [[ ${UI_MODE} == "dialog" ]]; then
    opts+=("--defaultno")
    if [[ ${default} == Yes ]]; then
      opts=("--title" "${title}" "--yesno" "${text}" 12 70)
    fi
  elif [[ ${UI_MODE} == "whiptail" ]]; then
    if [[ ${default} == No ]]; then
      opts+=("--defaultno")
    fi
  fi
  if ${UI_BIN} "${opts[@]}" 3>&1 1>&2 2>&3; then
    return 0
  fi
  return 1
}

ui_input(){
  local title=$1 text=$2 default=$3
  local result
  if [[ ${UI_MODE} == "whiptail" ]]; then
    result=$(${UI_BIN} --title "${title}" --inputbox "${text}" 12 70 "${default}" 3>&1 1>&2 2>&3) || exit 1
  else
    result=$(${UI_BIN} --title "${title}" --inputbox "${text}" 12 70 "${default}" 3>&1 1>&2 2>&3) || exit 1
  fi
  printf '%s' "${result}"
}

ui_menu(){
  local title=$1 text=$2
  shift 2
  local options=()
  options=("$@")
  local result
  if [[ ${UI_MODE} == "whiptail" ]]; then
    result=$(${UI_BIN} --title "${title}" --menu "${text}" 18 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || exit 1
  else
    result=$(${UI_BIN} --title "${title}" --menu "${text}" 18 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || exit 1
  fi
  printf '%s' "${result}"
}

source_existing_vars(){
  if [[ -f ${VARS_FILE} ]]; then
    # shellcheck disable=SC1090
    source "${VARS_FILE}"
  fi
}

trim(){
  local value=$*
  value=${value##+([[:space:]])}
  value=${value%%+([[:space:]])}
  printf '%s' "${value}"
}

read_schema_value(){
  local host=$1 key=$2 default=$3
  if [[ ! -f ${IP_SCHEMA_FILE} ]]; then
    printf '%s' "${default}"
    return 0
  fi
  local value
  value=$(awk -v host="${host}" -v key="${key}" '
    $1 ~ "^"host":" {found=1; next}
    found && $1 ~ "^"key":" {
      sub(/^[^:]*:[[:space:]]*/, "")
      gsub(/"/, "")
      gsub(/[\r\n]/, "")
      print
      exit
    }
    found && /^[^[:space:]]/ {exit}
  ' "${IP_SCHEMA_FILE}")
  value=$(trim "${value:-}")
  if [[ -z ${value} ]]; then
    printf '%s' "${default}"
  else
    printf '%s' "${value}"
  fi
}

detect_storage_targets(){
  if ! command -v pvesm >/dev/null 2>&1; then
    return 1
  fi
  while read -r store type status _; do
    [[ -z ${store} ]] && continue
    [[ ${store} == "Name" ]] && continue
    printf '%s|%s/%s\n' "${store}" "${type}" "${status}"
  done < <(pvesm status 2>/dev/null)
}

detect_templates(){
  if ! command -v pveam >/dev/null 2>&1; then
    return 1
  fi
  while read -r storage template _; do
    if [[ ${storage} == "storage" ]]; then
      continue
    fi
    [[ -z ${template} ]] && continue
    printf '%s|%s\n' "${storage}:${template}" "${storage}"
  done < <(pveam list 2>/dev/null | awk '{print $2" "$3}')
}

detect_bridges(){
  if ! command -v ip >/dev/null 2>&1; then
    return 1
  fi
  while read -r _ name _; do
    name=${name%:}
    [[ -z ${name} ]] && continue
    printf '%s|bridge\n' "${name}"
  done < <(ip -o link show type bridge 2>/dev/null)
}

detect_gateway(){
  if ! command -v ip >/dev/null 2>&1; then
    return 1
  fi
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

detect_dns_servers(){
  local servers=()
  if command -v resolvectl >/dev/null 2>&1; then
    servers=($(resolvectl dns 2>/dev/null | awk '{print $NF}' | tr ' ' '\n' | grep -E '^[0-9]'))
  fi
  if [[ ${#servers[@]} -eq 0 && -f /etc/resolv.conf ]]; then
    servers=($(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}'))
  fi
  printf '%s\n' "${servers[@]}"
}

detect_timezone(){
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl show -p Timezone --value 2>/dev/null
  fi
}

select_from_options(){
  local title=$1 prompt=$2 current=$3
  shift 3
  local raw_options=()
  raw_options=("$@")
  local options=()
  if [[ -n ${current:-} ]]; then
    options+=("__CURRENT__" "Aktueller Wert: ${current}")
  fi
  options+=(${raw_options[@]})
  options+=("__MANUAL__" "Manuelle Eingabe")
  local choice
  choice=$(ui_menu "${title}" "${prompt}" "${options[@]}")
  if [[ ${choice} == "__MANUAL__" ]]; then
    printf '%s' ""
    return 2
  elif [[ ${choice} == "__CURRENT__" ]]; then
    printf '%s' "${current}"
    return 0
  else
    printf '%s' "${choice}"
    return 0
  fi
}

prompt_storage(){
  local current=${RALF_STORAGE_TARGET:-}
  local menu=()
  local storage_opts=()
  if mapfile -t storage_opts < <(detect_storage_targets); then
    for entry in "${storage_opts[@]}"; do
      [[ -z ${entry} ]] && continue
      menu+=("${entry%%|*}" "${entry#*|}")
    done
  fi
  if [[ ${#menu[@]} -gt 0 ]]; then
    local selection
    selection=$(select_from_options "Storage" "Bitte Storage-Target wählen" "${current}" "${menu[@]}") || true
    if [[ -n ${selection} ]]; then
      RALF_STORAGE_TARGET=${selection}
      return
    fi
  fi
  RALF_STORAGE_TARGET=$(ui_input "Storage" "Storage-Target (z. B. local-lvm)" "${current}")
}

prompt_template(){
  local current=${RALF_TEMPLATE_PATH:-}
  local menu=()
  local template_opts=()
  if mapfile -t template_opts < <(detect_templates); then
    for entry in "${template_opts[@]}"; do
      [[ -z ${entry} ]] && continue
      menu+=("${entry%%|*}" "${entry#*|}")
    done
  fi
  if [[ ${#menu[@]} -gt 0 ]]; then
    local selection
    selection=$(select_from_options "Template" "Ubuntu Template auswählen" "${current}" "${menu[@]}") || true
    if [[ -n ${selection} ]]; then
      RALF_TEMPLATE_PATH=${selection}
      return
    fi
  fi
  RALF_TEMPLATE_PATH=$(ui_input "Template" "Template (z. B. local:vztmpl/ubuntu-24.04-standard_20240512.tar.zst)" "${current}")
}

prompt_bridge(){
  local current=${RALF_BRIDGE:-vmbr0}
  local menu=()
  local bridge_opts=()
  if mapfile -t bridge_opts < <(detect_bridges); then
    for entry in "${bridge_opts[@]}"; do
      [[ -z ${entry} ]] && continue
      menu+=("${entry%%|*}" "${entry#*|}")
    done
  fi
  if [[ ${#menu[@]} -gt 0 ]]; then
    local selection
    selection=$(select_from_options "Bridge" "Netzwerkbridge auswählen" "${current}" "${menu[@]}") || true
    if [[ -n ${selection} ]]; then
      RALF_BRIDGE=${selection}
      return
    fi
  fi
  RALF_BRIDGE=$(ui_input "Bridge" "Bridge (z. B. vmbr0)" "${current}")
}

prompt_gateway(){
  local current=${RALF_GATEWAY_IPV4:-}
  if [[ -z ${current} || ${current} == "ASK_RUNTIME" ]]; then
    local detected
    detected=$(detect_gateway || true)
    if [[ -n ${detected} ]]; then
      current=${detected}
    fi
  fi
  RALF_GATEWAY_IPV4=$(ui_input "Gateway" "Gateway IPv4" "${current}")
}

prompt_dns(){
  local current=${RALF_DNS_RESOLVER:-}
  if [[ -z ${current} || ${current} == "ASK_RUNTIME" ]]; then
    local servers
    servers=$(detect_dns_servers || true)
    if [[ -n ${servers} ]]; then
      current=$(printf '%s' "${servers}" | head -n1)
    fi
  fi
  RALF_DNS_RESOLVER=$(ui_input "DNS" "DNS Resolver IPv4" "${current:-1.1.1.1}")
}

prompt_backup(){
  local current_host=${RALF_BACKUP_HOST:-nas.home.arpa}
  local current_port=${RALF_BACKUP_PORT:-22}
  RALF_BACKUP_HOST=$(ui_input "Backup" "Backup Hostname (ssh://backup@HOST)" "${current_host}")
  RALF_BACKUP_PORT=$(ui_input "Backup" "Backup Port" "${current_port}")
}

prompt_timezone(){
  local current=${RALF_TIMEZONE:-}
  if [[ -z ${current} || ${current} == "ASK_RUNTIME" ]]; then
    local detected
    detected=$(detect_timezone || true)
    if [[ -n ${detected} ]]; then
      current=${detected}
    else
      current="Europe/Berlin"
    fi
  fi
  RALF_TIMEZONE=$(ui_input "Zeitzone" "Systemzeitzone" "${current}")
}

HOSTS=(
  "ralf-lxc|RALF_LXC_CTID|RALF_LXC_IPV4|RALF_LXC_GW|RALF_LXC_FQDN"
  "svc-postgres|POSTGRES_CTID|POSTGRES_IPV4|POSTGRES_GW|POSTGRES_FQDN"
  "svc-semaphore|SEMAPHORE_CTID|SEMAPHORE_IPV4|SEMAPHORE_GW|SEMAPHORE_FQDN"
  "svc-foreman|FOREMAN_CTID|FOREMAN_IPV4|FOREMAN_GW|FOREMAN_FQDN"
  "svc-n8n|N8N_CTID|N8N_IPV4|N8N_GW|N8N_FQDN"
  "svc-vaultwarden|VAULTWARDEN_CTID|VAULTWARDEN_IPV4|VAULTWARDEN_GW|VAULTWARDEN_FQDN"
)

declare -A HOST_VALUES

prompt_host_values(){
  for entry in "${HOSTS[@]}"; do
    IFS='|' read -r host ctid_var ip_var gw_var fqdn_var <<<"${entry}"
    local current_ctid=${!ctid_var:-}
    local current_ip=${!ip_var:-}
    local current_gw=${!gw_var:-}
    local current_fqdn=${!fqdn_var:-}
    if [[ -z ${current_ctid} || ${current_ctid} == "ASK_RUNTIME" ]]; then
      current_ctid=$(read_schema_value "${host}" "ctid" "")
    fi
    if [[ -z ${current_ip} || ${current_ip} == "ASK_RUNTIME" ]]; then
      current_ip=$(read_schema_value "${host}" "ipv4" "")
    fi
    if [[ -z ${current_gw} || ${current_gw} == "ASK_RUNTIME" ]]; then
      current_gw=$(read_schema_value "${host}" "gateway" "${RALF_GATEWAY_IPV4:-}" )
    fi
    if [[ -z ${current_fqdn} || ${current_fqdn} == "ASK_RUNTIME" ]]; then
      current_fqdn=$(read_schema_value "${host}" "fqdn" "${host}.home.arpa")
    fi

    local ctid_prompt="CTID für ${host}"
    local ip_prompt="IPv4 (CIDR) für ${host}"
    local gw_prompt="Gateway für ${host}"
    local fqdn_prompt="FQDN für ${host}"

    HOST_VALUES[${ctid_var}]=$(ui_input "${host}" "${ctid_prompt}" "${current_ctid}")
    HOST_VALUES[${ip_var}]=$(ui_input "${host}" "${ip_prompt}" "${current_ip}")
    HOST_VALUES[${gw_var}]=$(ui_input "${host}" "${gw_prompt}" "${current_gw}")
    HOST_VALUES[${fqdn_var}]=$(ui_input "${host}" "${fqdn_prompt}" "${current_fqdn}")
  done
}

prompt_dns_list(){
  local dns_servers
  dns_servers=($(detect_dns_servers || true))
  local default1=${dns_servers[0]:-1.1.1.1}
  local default2=${dns_servers[1]:-9.9.9.9}
  local stored1=$(awk '/ralf-lxc:/ {found=1} found && /- / {gsub(/"/, "", $2); print $2; exit}' "${IP_SCHEMA_FILE}" 2>/dev/null || true)
  local stored2=$(awk '/ralf-lxc:/ {found=1} found && /- / {gsub(/"/, "", $2); if (seen==1) {print $2; exit} seen=1 }' "${IP_SCHEMA_FILE}" 2>/dev/null || true)
  RALF_LXC_DNS1=$(ui_input "ralf-lxc" "Primärer DNS für ralf-lxc" "${stored1:-${default1}}")
  RALF_LXC_DNS2=$(ui_input "ralf-lxc" "Sekundärer DNS für ralf-lxc" "${stored2:-${default2}}")
}

write_preflight_file(){
  cat <<EOF > "${VARS_FILE}"
# shellcheck shell=bash
# Datei vom grafischen Installer generiert. Werte bei Bedarf anpassen.
export RALF_STORAGE_TARGET="${RALF_STORAGE_TARGET}"
export RALF_TEMPLATE_PATH="${RALF_TEMPLATE_PATH}"
export RALF_BRIDGE="${RALF_BRIDGE}"
export RALF_DNS_RESOLVER="${RALF_DNS_RESOLVER}"
export RALF_GATEWAY_IPV4="${RALF_GATEWAY_IPV4}"
export RALF_BACKUP_HOST="${RALF_BACKUP_HOST}"
export RALF_BACKUP_PORT="${RALF_BACKUP_PORT}"
export RALF_EXPECTED_PVE_SERVICES="${RALF_EXPECTED_PVE_SERVICES:-pvedaemon pveproxy pvestatd}"
export RALF_TIMEZONE="${RALF_TIMEZONE}"

# Container-spezifische Variablen
export RALF_LXC_CTID="${HOST_VALUES[RALF_LXC_CTID]}"
export RALF_LXC_IPV4="${HOST_VALUES[RALF_LXC_IPV4]}"
export RALF_LXC_GW="${HOST_VALUES[RALF_LXC_GW]}"
export RALF_LXC_FQDN="${HOST_VALUES[RALF_LXC_FQDN]}"
export RALF_LXC_CPUS="${RALF_LXC_CPUS:-4}"
export RALF_LXC_MEMORY="${RALF_LXC_MEMORY:-4096}"
export RALF_LXC_DISK="${RALF_LXC_DISK:-32G}"

export POSTGRES_CTID="${HOST_VALUES[POSTGRES_CTID]}"
export POSTGRES_IPV4="${HOST_VALUES[POSTGRES_IPV4]}"
export POSTGRES_GW="${HOST_VALUES[POSTGRES_GW]}"
export POSTGRES_FQDN="${HOST_VALUES[POSTGRES_FQDN]}"

export SEMAPHORE_CTID="${HOST_VALUES[SEMAPHORE_CTID]}"
export SEMAPHORE_IPV4="${HOST_VALUES[SEMAPHORE_IPV4]}"
export SEMAPHORE_GW="${HOST_VALUES[SEMAPHORE_GW]}"
export SEMAPHORE_FQDN="${HOST_VALUES[SEMAPHORE_FQDN]}"

export FOREMAN_CTID="${HOST_VALUES[FOREMAN_CTID]}"
export FOREMAN_IPV4="${HOST_VALUES[FOREMAN_IPV4]}"
export FOREMAN_GW="${HOST_VALUES[FOREMAN_GW]}"
export FOREMAN_FQDN="${HOST_VALUES[FOREMAN_FQDN]}"

export N8N_CTID="${HOST_VALUES[N8N_CTID]}"
export N8N_IPV4="${HOST_VALUES[N8N_IPV4]}"
export N8N_GW="${HOST_VALUES[N8N_GW]}"
export N8N_FQDN="${HOST_VALUES[N8N_FQDN]}"

export VAULTWARDEN_CTID="${HOST_VALUES[VAULTWARDEN_CTID]}"
export VAULTWARDEN_IPV4="${HOST_VALUES[VAULTWARDEN_IPV4]}"
export VAULTWARDEN_GW="${HOST_VALUES[VAULTWARDEN_GW]}"
export VAULTWARDEN_FQDN="${HOST_VALUES[VAULTWARDEN_FQDN]}"

export RALF_LXC_DNS1="${RALF_LXC_DNS1}"
export RALF_LXC_DNS2="${RALF_LXC_DNS2}"
EOF
}

write_ip_schema(){
  cat <<YAML > "${IP_SCHEMA_FILE}"
---
# Netzschema für Ralf. Werte werden durch den Installer gepflegt.
# Sortiere CTIDs nach führender Ziffer (1xx=Control, 2xx=Data, 3xx=Apps, ...).

ralf-lxc:
  ctid: "${HOST_VALUES[RALF_LXC_CTID]}"
  ipv4: "${HOST_VALUES[RALF_LXC_IPV4]}"
  gateway: "${HOST_VALUES[RALF_LXC_GW]}"
  fqdn: "${HOST_VALUES[RALF_LXC_FQDN]}"
  dns:
    - "${RALF_LXC_DNS1}"
    - "${RALF_LXC_DNS2}"
svc-postgres:
  ctid: "${HOST_VALUES[POSTGRES_CTID]}"
  ipv4: "${HOST_VALUES[POSTGRES_IPV4]}"
  gateway: "${HOST_VALUES[POSTGRES_GW]}"
  fqdn: "${HOST_VALUES[POSTGRES_FQDN]}"
svc-semaphore:
  ctid: "${HOST_VALUES[SEMAPHORE_CTID]}"
  ipv4: "${HOST_VALUES[SEMAPHORE_IPV4]}"
  gateway: "${HOST_VALUES[SEMAPHORE_GW]}"
  fqdn: "${HOST_VALUES[SEMAPHORE_FQDN]}"
svc-foreman:
  ctid: "${HOST_VALUES[FOREMAN_CTID]}"
  ipv4: "${HOST_VALUES[FOREMAN_IPV4]}"
  gateway: "${HOST_VALUES[FOREMAN_GW]}"
  fqdn: "${HOST_VALUES[FOREMAN_FQDN]}"
svc-n8n:
  ctid: "${HOST_VALUES[N8N_CTID]}"
  ipv4: "${HOST_VALUES[N8N_IPV4]}"
  gateway: "${HOST_VALUES[N8N_GW]}"
  fqdn: "${HOST_VALUES[N8N_FQDN]}"
svc-vaultwarden:
  ctid: "${HOST_VALUES[VAULTWARDEN_CTID]}"
  ipv4: "${HOST_VALUES[VAULTWARDEN_IPV4]}"
  gateway: "${HOST_VALUES[VAULTWARDEN_GW]}"
  fqdn: "${HOST_VALUES[VAULTWARDEN_FQDN]}"
YAML
}

write_summary(){
  cat <<SUMMARY > "${SUMMARY_FILE}"
Ralf Installer Zusammenfassung
==============================

Storage: ${RALF_STORAGE_TARGET}
Template: ${RALF_TEMPLATE_PATH}
Bridge: ${RALF_BRIDGE}
Gateway: ${RALF_GATEWAY_IPV4}
DNS Resolver: ${RALF_DNS_RESOLVER}
Backup Host: ${RALF_BACKUP_HOST}:${RALF_BACKUP_PORT}
Timezone: ${RALF_TIMEZONE}

Container:
  ralf-lxc -> CTID ${HOST_VALUES[RALF_LXC_CTID]}, ${HOST_VALUES[RALF_LXC_IPV4]}, ${HOST_VALUES[RALF_LXC_FQDN]}
  svc-postgres -> CTID ${HOST_VALUES[POSTGRES_CTID]}, ${HOST_VALUES[POSTGRES_IPV4]}, ${HOST_VALUES[POSTGRES_FQDN]}
  svc-semaphore -> CTID ${HOST_VALUES[SEMAPHORE_CTID]}, ${HOST_VALUES[SEMAPHORE_IPV4]}, ${HOST_VALUES[SEMAPHORE_FQDN]}
  svc-foreman -> CTID ${HOST_VALUES[FOREMAN_CTID]}, ${HOST_VALUES[FOREMAN_IPV4]}, ${HOST_VALUES[FOREMAN_FQDN]}
  svc-n8n -> CTID ${HOST_VALUES[N8N_CTID]}, ${HOST_VALUES[N8N_IPV4]}, ${HOST_VALUES[N8N_FQDN]}
  svc-vaultwarden -> CTID ${HOST_VALUES[VAULTWARDEN_CTID]}, ${HOST_VALUES[VAULTWARDEN_IPV4]}, ${HOST_VALUES[VAULTWARDEN_FQDN]}
SUMMARY
}

main(){
  init_ui
  source_existing_vars
  ui_msg "Ralf Installer" "Dieser Assistent sammelt Laufzeitwerte für Preflight und Containerprovisionierung."

  prompt_storage
  prompt_template
  prompt_bridge
  prompt_gateway
  prompt_dns
  prompt_backup
  prompt_timezone
  prompt_host_values
  prompt_dns_list

  write_preflight_file
  write_ip_schema
  write_summary

  ui_msg "Abschluss" "Konfiguration aktualisiert. Zusammenfassung unter ${SUMMARY_FILE}."
  log INFO "Installer abgeschlossen"
}

main "$@"
