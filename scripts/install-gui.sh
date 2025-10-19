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
  if [[ -n ${LOGGER_BIN:-} ]]; then
    "${LOGGER_BIN}" -t "${LOG_TAG}" "${level}: ${message}" || true
  fi
  printf '%s: %s\n' "${level}" "${message}"
}

UI_BIN=""
UI_TOOL=""

is_remote_session(){
  if [[ -n ${SSH_CONNECTION:-} || -n ${SSH_CLIENT:-} || -n ${SSH_TTY:-} || -n ${REMOTEHOST:-} ]]; then
    return 0
  fi
  return 1
}

init_ui(){
  local preferred fallback
  if is_remote_session; then
    preferred="whiptail"
    fallback="dialog"
    log "INFO" "Entfernte Sitzung erkannt – bevorzuge 'whiptail' als UI."
  else
    preferred="dialog"
    fallback="whiptail"
    log "INFO" "Lokale Sitzung erkannt – bevorzuge 'dialog' als UI."
  fi

  for candidate in "${preferred}" "${fallback}"; do
    if [[ -n ${candidate} ]] && command -v "${candidate}" >/dev/null 2>&1; then
      UI_BIN=$(command -v "${candidate}")
      UI_TOOL="${candidate}"
      break
    fi
  done

  if [[ -z ${UI_BIN} ]]; then
    log "ERROR" "Weder 'dialog' noch 'whiptail' wurde gefunden. Bitte 'apt install dialog whiptail' ausführen und den Installer erneut starten."
    exit 1
  fi

  if [[ ${UI_TOOL} == dialog ]]; then
    export DIALOGOPTS="--clear --no-collapse --visit-items --mouse"
    log "INFO" "Verwende 'dialog' mit aktivierter Mausunterstützung."
  else
    export NEWT_COLORS=${NEWT_COLORS:-}
    log "INFO" "Verwende 'whiptail'. Mausunterstützung wird bereitgestellt, sofern Terminal und libnewt dies ermöglichen."
  fi
}

ui_msg(){
  local title=$1 text=$2
  if [[ ${UI_TOOL} == dialog ]]; then
    "${UI_BIN}" --title "${title}" --ok-label "Weiter" --msgbox "${text}" 12 78
  else
    "${UI_BIN}" --title "${title}" --ok-button "Weiter" --msgbox "${text}" 12 78
  fi
}

ui_yesno(){
  local title=$1 text=$2 default=${3:-Yes}
  local opts=(--title "${title}" --yesno "${text}" 12 78)
  if [[ ${default} == No ]]; then
    opts+=(--defaultno)
  fi
  if [[ ${UI_TOOL} == dialog ]]; then
    opts+=(--yes-label "Ja" --no-label "Nein")
  else
    opts+=(--yes-button "Ja" --no-button "Nein")
  fi
  if "${UI_BIN}" "${opts[@]}" 3>&1 1>&2 2>&3; then
    return 0
  fi
  return 1
}

ui_input(){
  local title=$1 text=$2 default=$3
  local result
  if [[ ${UI_TOOL} == dialog ]]; then
    result=$("${UI_BIN}" --title "${title}" --inputbox "${text}" 12 78 "${default}" 3>&1 1>&2 2>&3) || exit 1
  else
    result=$("${UI_BIN}" --title "${title}" --ok-button "Weiter" --cancel-button "Abbrechen" --inputbox "${text}" 12 78 "${default}" 3>&1 1>&2 2>&3) || exit 1
  fi
  printf '%s' "${result}"
}

ui_menu(){
  local title=$1 text=$2
  shift 2
  local options=("$@")
  local base_opts=(--title "${title}" --menu "${text}" 18 78 10)
  if [[ ${UI_TOOL} == dialog ]]; then
    base_opts+=(--ok-label "Weiter" --cancel-label "Abbrechen")
  else
    base_opts+=(--ok-button "Weiter" --cancel-button "Abbrechen")
  fi
  local result
  result=$("${UI_BIN}" "${base_opts[@]}" "${options[@]}" 3>&1 1>&2 2>&3) || exit 1
  printf '%s' "${result}"
}

ui_textbox(){
  local title=$1 text=$2
  local tmp
  tmp=$(mktemp)
  printf '%s\n' "${text}" >"${tmp}"
  if [[ ${UI_TOOL} == dialog ]]; then
    "${UI_BIN}" --title "${title}" --ok-label "Zurück" --textbox "${tmp}" 20 90
  else
    "${UI_BIN}" --title "${title}" --ok-button "Zurück" --textbox "${tmp}" 20 90
  fi
  rm -f "${tmp}"
}

ui_menu_optional(){
  local title=$1 text=$2
  shift 2
  local options=("$@")
  local base_opts=(--title "${title}" --menu "${text}" 20 90 12)
  if [[ ${UI_TOOL} == dialog ]]; then
    base_opts+=(--ok-label "Auswählen" --cancel-label "Zurück")
  else
    base_opts+=(--ok-button "Auswählen" --cancel-button "Zurück")
  fi
  local result
  if result=$("${UI_BIN}" "${base_opts[@]}" "${options[@]}" 3>&1 1>&2 2>&3); then
    printf '%s' "${result}"
    return 0
  fi
  return 1
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
    mapfile -t servers < <(resolvectl dns 2>/dev/null | awk '{print $NF}' | tr ' ' '\n' | grep -E '^[0-9]')
  fi
  if [[ ${#servers[@]} -eq 0 && -f /etc/resolv.conf ]]; then
    mapfile -t servers < <(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}')
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
  options+=("${raw_options[@]}")
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

CHECK_ORDER=()
declare -A CHECK_STATUS
declare -A CHECK_DETAILS
declare -A TASK_HINTS
declare -A MENU_TASK_INDEX
PREFLIGHT_RAW_OUTPUT=""
PREFLIGHT_EXIT_STATUS=0

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
  local -a dns_servers=()
  mapfile -t dns_servers < <(detect_dns_servers || true)
  local default1=${dns_servers[0]:-1.1.1.1}
  local default2=${dns_servers[1]:-9.9.9.9}
  local stored1=""
  stored1=$(awk '/ralf-lxc:/ {found=1} found && /- / {gsub(/"/, "", $2); print $2; exit}' "${IP_SCHEMA_FILE}" 2>/dev/null || true)
  local stored2=""
  stored2=$(awk '/ralf-lxc:/ {found=1} found && /- / {gsub(/"/, "", $2); if (seen==1) {print $2; exit} seen=1 }' "${IP_SCHEMA_FILE}" 2>/dev/null || true)
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

init_task_hints(){
  read -r -d '' TASK_HINTS["Pflichtprogramme verfügbar"] <<'EOF'
Installiere die fehlenden Proxmox-Werkzeuge auf dem Host. Ein vollständiges `apt install proxmox-ve` stellt alle CLI-Binaries (pct, qm, pveversion, pvesh, pvesm, pveam, lsblk) bereit. Alternativ lassen sich die Pakete `pve-cluster`, `pve-manager`, `pve-container`, `pve-qemu-kvm` und `proxmox-backup-client` einzeln nachinstallieren. Wiederhole anschließend `./scripts/preflight.sh`.
EOF
  read -r -d '' TASK_HINTS["Proxmox Dienste"] <<'EOF'
Prüfe den Zustand der Proxmox-Systemd-Units mit `systemctl status pvedaemon pveproxy pvestatd`. Stelle sicher, dass keine Wartungsarbeiten laufen und korrigiere fehlgeschlagene Starts (z. B. durch Neustart des Hosts oder das Schließen offener Updates mit `apt full-upgrade`).
EOF
  read -r -d '' TASK_HINTS["Storage vorhanden"] <<'EOF'
Hinterlege ein gültiges Storage-Target in `infra/network/preflight.vars.source` (Variable `RALF_STORAGE_TARGET`). Über `pvesm status` kannst du bestehende Storages prüfen. Das Ubuntu-Template sowie alle Container werden auf diesem Storage abgelegt.
EOF
  read -r -d '' TASK_HINTS["Template verfügbar"] <<'EOF'
Synchronisiere das Proxmox-Template-Repository (`pveam update`) und lade das gewünschte Ubuntu-Template mit `pveam download <storage> <template>`. Hinterlege den Pfad in `RALF_TEMPLATE_PATH`, z. B. `local:vztmpl/ubuntu-24.04-standard_*.tar.zst`.
EOF
  read -r -d '' TASK_HINTS["Bridge vorhanden"] <<'EOF'
Lege die in `RALF_BRIDGE` definierte Netzwerk-Bridge (standardmäßig `vmbr0`) an oder aktiviere sie. Verwende dazu die Proxmox-GUI oder bearbeite `/etc/network/interfaces`. Anschließend `ifreload -a` oder einen Host-Neustart durchführen.
EOF
  read -r -d '' TASK_HINTS["Gateway erreichbar"] <<'EOF'
Trage das korrekte Default-Gateway (IPv4) in `RALF_GATEWAY_IPV4` ein und stelle sicher, dass die Route erreichbar ist (`ping -c1 <gateway>`). Bei VLAN- oder Routing-Anpassungen ggf. Bridge- oder Switch-Konfiguration prüfen.
EOF
  read -r -d '' TASK_HINTS["DNS-Auflösung"] <<'EOF'
Überprüfe den Resolver in `RALF_DNS_RESOLVER`. Teste DNS-Auflösungen mit `dig proxmox.com @<resolver>` oder `getent hosts proxmox.com`. Passe ggf. `/etc/resolv.conf` bzw. die Systemd-Resolved-Konfiguration an.
EOF
  read -r -d '' TASK_HINTS["CTIDs frei"] <<'EOF'
Vergleiche die im Netzschema (`infra/network/ip-schema.yml`) hinterlegten CTIDs mit bestehenden LXC-Containern (`pct list`). Passe kollidierende IDs an und aktualisiere die Datei, damit jede geplante Instanz eine freie CTID erhält.
EOF
  read -r -d '' TASK_HINTS["FQDN-Validierung"] <<'EOF'
Sorge für eindeutige Fully-Qualified-Domain-Names im Netzschema. Jeder Eintrag unter `infra/network/ip-schema.yml` darf nur einmal pro Host vorkommen. Passe doppelte Namen an und speichere die Datei.
EOF
  read -r -d '' TASK_HINTS["Zeit-Sync"] <<'EOF'
Aktiviere die Zeit-Synchronisation mit `timedatectl set-ntp true` oder konfiguriere einen lokalen NTP-Dienst (chrony/systemd-timesyncd). Stelle sicher, dass ausgehender UDP-Verkehr zu den Zeitservern erlaubt ist.
EOF
  read -r -d '' TASK_HINTS["SSH-Pubkey"] <<'EOF'
Lege unter `/root/.ssh/` einen öffentlichen Schlüssel ab (bevorzugt `id_ed25519.pub`). Erzeuge ihn bei Bedarf mit `ssh-keygen -t ed25519 -C "ralf@host"`. Der Schlüssel wird für automatisierte Zugriffe auf Container benötigt.
EOF
  read -r -d '' TASK_HINTS["Backup-Host erreichbar"] <<'EOF'
Prüfe die Erreichbarkeit des Borgmatic-Backup-Ziels (`RALF_BACKUP_HOST` und `RALF_BACKUP_PORT`). Stelle sicher, dass der Host per SSH erreichbar ist (Firewall, DNS, Routing). Nutze `nc -z <host> <port>` oder `ssh backup@<host>` zur Verifikation.
EOF
}

reset_preflight_state(){
  CHECK_ORDER=()
  CHECK_STATUS=()
  CHECK_DETAILS=()
  MENU_TASK_INDEX=()
  PREFLIGHT_RAW_OUTPUT=""
}

status_badge(){
  local status=$1
  case ${status} in
    PASS) printf '[OK]';;
    WARN) printf '[WARN]';;
    FAIL) printf '[TODO]';;
    *) printf '[?]';;
  esac
}

parse_preflight_output(){
  local file=$1
  local detail_buffer=""
  local in_checks=0
  local line
  while IFS= read -r line; do
    case ${line} in
      'PASS: '*)
        in_checks=1
        local name=${line#PASS: }
        if [[ -z ${CHECK_STATUS["${name}"]:-} ]]; then
          CHECK_ORDER+=("${name}")
        fi
        local status="PASS"
        if [[ ${detail_buffer} == *$'WARN:'* ]]; then
          status="WARN"
        fi
        CHECK_STATUS["${name}"]="${status}"
        CHECK_DETAILS["${name}"]="${detail_buffer}"
        detail_buffer=""
        ;;
      'FAIL: '*)
        in_checks=1
        local name=${line#FAIL: }
        if [[ -z ${CHECK_STATUS["${name}"]:-} ]]; then
          CHECK_ORDER+=("${name}")
        fi
        CHECK_STATUS["${name}"]="FAIL"
        CHECK_DETAILS["${name}"]="${detail_buffer}"
        detail_buffer=""
        ;;
      'INFO: '*|'WARN: '*|'ERROR: '*)
        if (( in_checks )); then
          if [[ -n ${detail_buffer} ]]; then
            detail_buffer+=$'\n'
          fi
          detail_buffer+="${line}"
        fi
        ;;
      *)
        ;;
    esac
  done <"${file}"
}

run_preflight_capture(){
  reset_preflight_state
  local tmp
  tmp=$(mktemp)
  log INFO "Starte Preflight zur Aufgaben-Ermittlung"
  if "${PROJECT_ROOT}/scripts/preflight.sh" >"${tmp}" 2>&1; then
    PREFLIGHT_EXIT_STATUS=0
  else
    PREFLIGHT_EXIT_STATUS=$?
  fi
  PREFLIGHT_RAW_OUTPUT=$(<"${tmp}")
  parse_preflight_output "${tmp}"
  rm -f "${tmp}"
}

compose_task_message(){
  local name=$1
  local status=${CHECK_STATUS["${name}"]:-?}
  local detail=${CHECK_DETAILS["${name}"]:-}
  local hint=${TASK_HINTS["${name}"]:-}
  local message="Status: ${status}"
  if [[ -n ${detail} ]]; then
    message+=$'\n\nLetzte Ausgabe:\n'
    message+="${detail}"
  fi
  if [[ -n ${hint} ]]; then
    message+=$'\n\nEmpfohlene nächsten Schritte:\n'
    message+="${hint}"
  fi
  printf '%s' "${message}"
}

show_task_details(){
  local name=$1
  local message
  message=$(compose_task_message "${name}")
  ui_textbox "${name}" "${message}"
}

show_preflight_log(){
  if [[ -z ${PREFLIGHT_RAW_OUTPUT} ]]; then
    ui_msg "Preflight" "Es liegt noch keine Preflight-Ausgabe vor."
    return
  fi
  ui_textbox "Preflight-Protokoll" "${PREFLIGHT_RAW_OUTPUT}"
}

guided_task_walkthrough(){
  local pending=()
  local name status
  for name in "${CHECK_ORDER[@]}"; do
    status=${CHECK_STATUS["${name}"]:-PASS}
    if [[ ${status} == FAIL || ${status} == WARN ]]; then
      pending+=("${name}")
    fi
  done
  if [[ ${#pending[@]} -eq 0 ]]; then
    ui_msg "Geführte Prüfung" "Alle Punkte sind bereits abgeschlossen. Du kannst den Preflight über das Menü erneut ausführen."
    return
  fi
  for name in "${pending[@]}"; do
    show_task_details "${name}"
    if ! ui_yesno "Fortfahren" "Weiter mit dem nächsten Punkt?" Yes; then
      return
    fi
  done
  if ui_yesno "Preflight" "Soll der Preflight jetzt erneut ausgeführt werden?" Yes; then
    run_preflight_capture
  fi
}

preflight_dashboard(){
  while true; do
    local options=()
    MENU_TASK_INDEX=()
    local idx=1
    local name status badge
    for name in "${CHECK_ORDER[@]}"; do
      status=${CHECK_STATUS["${name}"]:-?}
      badge=$(status_badge "${status}")
      local tag="task${idx}"
      options+=("${tag}" "${badge} ${name}")
      MENU_TASK_INDEX["${tag}"]="${name}"
      ((idx++))
    done
    options+=("walkthrough" "Geführte Bearbeitung offener Punkte")
    options+=("rerun" "Preflight erneut ausführen")
    options+=("log" "Komplette Preflight-Ausgabe anzeigen")
    options+=("finish" "Installer abschließen")

    local header="Statusübersicht"
    local summary="Letzter Preflight-Lauf: "
    if (( PREFLIGHT_EXIT_STATUS == 0 )); then
      summary+="erfolgreich"
    else
      summary+="mit Fehlern (Exit ${PREFLIGHT_EXIT_STATUS})"
    fi
    local selection
    if ! selection=$(ui_menu_optional "${header}" "${summary}\n\nKlicke mit der Maus oder nutze die Tastatur, um Details einzusehen." "${options[@]}"); then
      if ui_yesno "Installer" "Dialog schließen und zum Abschluss springen?" No; then
        return
      fi
      continue
    fi

    case ${selection} in
      task*)
        local task_name=${MENU_TASK_INDEX["${selection}"]}
        show_task_details "${task_name}"
        ;;
      walkthrough)
        guided_task_walkthrough
        ;;
      rerun)
        ui_msg "Preflight" "Der Preflight wird erneut ausgeführt."
        run_preflight_capture
        ;;
      log)
        show_preflight_log
        ;;
      finish)
        return
        ;;
    esac
  done
}

main(){
  init_ui
  init_task_hints
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

  ui_msg "Preflight" "Konfiguration gespeichert. Der grafische Assistent analysiert jetzt die Ergebnisse von scripts/preflight.sh und führt dich durch offene Punkte."
  run_preflight_capture
  preflight_dashboard

  ui_msg "Abschluss" "Konfiguration aktualisiert. Zusammenfassung unter ${SUMMARY_FILE}. Die Preflight-Aufgaben kannst du jederzeit erneut mit ./scripts/preflight.sh prüfen."
  log INFO "Installer abgeschlossen"
}

main "$@"
