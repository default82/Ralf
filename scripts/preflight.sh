#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2317 # Prüf-Funktionen werden indirekt über run_check aufgerufen

LOG_TAG=${LOG_TAG:-ralf-preflight}
LOGGER_BIN=$(command -v logger || true)
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VARS_FILE="${PROJECT_ROOT}/infra/network/preflight.vars.source"
IP_SCHEMA="${PROJECT_ROOT}/infra/network/ip-schema.yml"
DEBUG=${DEBUG:-0}
PVE_NODE_NAME=${PVE_NODE_NAME:-$(hostname -s)}
REPORT_DIR=${RALF_PREFLIGHT_REPORT_DIR:-${PROJECT_ROOT}/logs}
REPORT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${REPORT_DIR}/preflight-report-${REPORT_TIMESTAMP}.txt"
INSTALL_PROXMOX=0
PROXMOX_INSTALL_PERFORMED=0

log()
{
  local level=$1; shift
  local message=$*
  if [[ -n ${LOGGER_BIN:-} ]]; then
    # logger darf nicht zum Abbruch führen
    "${LOGGER_BIN}" -t "${LOG_TAG}" "${level}: ${message}" || true
  fi
  printf '%s: %s\n' "${level}" "${message}"
}

log_debug() { [[ ${DEBUG} -eq 1 ]] && log "DEBUG" "$*"; }
log_info() { log "INFO" "$*"; }
log_warn() { log "WARN" "$*"; }
log_error() { log "ERROR" "$*"; }

ensure_report_directory()
{
  if [[ -d ${REPORT_DIR} ]]; then
    return 0
  fi
  if mkdir -p "${REPORT_DIR}"; then
    log_debug "Report-Verzeichnis ${REPORT_DIR} erstellt"
    return 0
  fi
  log_warn "Report-Verzeichnis ${REPORT_DIR} konnte nicht erstellt werden"
  return 1
}

append_block()
{
  local title=$1
  {
    printf '## %s\n' "${title}"
    cat
    printf '\n'
  } >>"${REPORT_FILE}"
}

pretty_print_json()
{
  if ! command -v python3 >/dev/null 2>&1; then
    cat
    return 0
  fi
  python3 - <<'PY' 2>/dev/null || cat
import json
import sys

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    sys.stdout.write(raw)
else:
    json.dump(data, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
PY
}

collect_pvesh_json()
{
  local title=$1
  local path=$2
  shift 2
  local -a args=("$@")
  if ! command -v pvesh >/dev/null 2>&1; then
    append_block "${title}" <<<'pvesh nicht verfügbar'
    return 0
  fi
  local -a cmd=(pvesh get "${path}" --output-format json)
  if [[ ${#args[@]} -gt 0 ]]; then
    cmd+=("${args[@]}")
  fi
  local output
  if output=$("${cmd[@]}" 2>&1); then
    append_block "${title}" <<<"$(printf '%s' "${output}" | pretty_print_json)"
  else
    append_block "${title}" <<<"Befehl fehlgeschlagen: ${cmd[*]}\n${output}"
  fi
}

collect_system_snapshot()
{
  if ! ensure_report_directory; then
    log_warn "Überspringe Berichtserstellung, da das Verzeichnis nicht erstellt werden konnte"
    return 1
  fi

  {
    printf '# Ralf Preflight Systembericht\n'
    printf '# Generiert: %s\n\n' "${REPORT_TIMESTAMP}"
  } >"${REPORT_FILE}"

  local output

  if output=$(hostnamectl 2>&1); then
    append_block 'Systemübersicht' <<<"${output}"
  else
    append_block 'Systemübersicht' <<<"hostnamectl fehlgeschlagen\n${output}"
  fi

  if command -v lscpu >/dev/null 2>&1 && output=$(lscpu 2>&1); then
    append_block 'CPU-Informationen' <<<"${output}"
  else
    append_block 'CPU-Informationen' <<<"lscpu nicht verfügbar"
  fi

  if command -v free >/dev/null 2>&1 && output=$(free -h 2>&1); then
    append_block 'Arbeitsspeicher' <<<"${output}"
  else
    append_block 'Arbeitsspeicher' <<<"free nicht verfügbar"
  fi

  if command -v lspci >/dev/null 2>&1 && output=$(lspci 2>&1); then
    append_block 'PCI-Geräte' <<<"${output}"
  fi

  if command -v lsblk >/dev/null 2>&1 && output=$(lsblk --output NAME,FSTYPE,SIZE,MOUNTPOINT,TYPE 2>&1); then
    append_block 'Blockgeräte' <<<"${output}"
  else
    append_block 'Blockgeräte' <<<"lsblk nicht verfügbar"
  fi

  if command -v df >/dev/null 2>&1 && output=$(df -hT 2>&1); then
    append_block 'Dateisystemauslastung' <<<"${output}"
  fi

  if command -v zpool >/dev/null 2>&1 && output=$(zpool status 2>&1); then
    append_block 'ZFS Zpool Status' <<<"${output}"
  fi

  if command -v pveversion >/dev/null 2>&1 && output=$(pveversion -v 2>&1); then
    append_block 'Proxmox VE Version' <<<"${output}"
  fi

  if command -v pct >/dev/null 2>&1 && output=$(pct list 2>&1); then
    append_block 'Vorhandene Container' <<<"${output}"
  fi

  if command -v qm >/dev/null 2>&1 && output=$(qm list 2>&1); then
    append_block 'Vorhandene VMs' <<<"${output}"
  fi

  collect_pvesh_json "Cluster Status" "/cluster/status"
  collect_pvesh_json "Cluster Ressourcen (Nodes)" "/cluster/resources" --type node
  collect_pvesh_json "Cluster Ressourcen (Storage)" "/cluster/resources" --type storage
  collect_pvesh_json "Cluster Ressourcen (VM/CT)" "/cluster/resources" --type vm
  collect_pvesh_json "Node ${PVE_NODE_NAME} Disks" "/nodes/${PVE_NODE_NAME}/disks/list"

  log_info "Systembericht gespeichert unter ${REPORT_FILE}"
}

load_vars()
{
  if [[ -f ${VARS_FILE} ]]; then
    # shellcheck disable=SC1090
    source "${VARS_FILE}"
    log_info "Variablen aus ${VARS_FILE} geladen"
  else
    log_warn "${VARS_FILE} nicht gefunden; nutze Standardwerte"
  fi
}

# shellcheck disable=SC2317
check_pve_services()
{
  local services_str=${RALF_EXPECTED_PVE_SERVICES:-"pvedaemon pveproxy pvestatd"}
  local -a services=()
  read -r -a services <<<"${services_str}"
  local missing=""
  local service
  local services=()
  read -r -a services <<<"${services_str}"
  local missing=()
  for service in "${services[@]}"; do
    if [[ -z ${service} ]]; then
      continue
    fi
    if ! systemctl is-active --quiet "${service}"; then
      if [[ -n ${missing} ]]; then
        missing+=" "
      fi
      missing+="${service}"
    fi
  done
  if [[ -n ${missing} ]]; then
    log_error "Folgende PVE-Dienste sind inaktiv: ${missing}"
    return 1
  fi
  log_info "Alle erwarteten PVE-Dienste sind aktiv"
}

# shellcheck disable=SC2317
is_placeholder()
{
  local value=${1:-}
  [[ -z ${value} || ${value} == ASK_RUNTIME || ${value} == *ASK_RUNTIME* ]]
}

# shellcheck disable=SC2317
check_storage()
{
  if is_placeholder "${RALF_STORAGE_TARGET:-}"; then
    log_warn "RALF_STORAGE_TARGET ist nicht gesetzt; überspringe Storage-Prüfung"
    return 0
  fi
  if ! command -v pvesm >/dev/null 2>&1; then
    log_warn "pvesm nicht verfügbar; überspringe Storage-Prüfung"
    return 0
  fi
  if pvesm status --storage "${RALF_STORAGE_TARGET}" >/dev/null 2>&1; then
    log_info "Storage ${RALF_STORAGE_TARGET} verfügbar"
  else
    log_error "Storage ${RALF_STORAGE_TARGET} nicht gefunden"
    return 1
  fi
}

# shellcheck disable=SC2317
check_template()
{
  if is_placeholder "${RALF_TEMPLATE_PATH:-}"; then
    log_warn "RALF_TEMPLATE_PATH ist nicht gesetzt; überspringe Template-Prüfung"
    return 0
  fi
  if ! command -v pveam >/dev/null 2>&1; then
    log_warn "pveam nicht verfügbar; überspringe Template-Prüfung"
    return 0
  fi
  fi
  if ! command -v pveam >/dev/null 2>&1; then
    log_warn "pveam nicht verfügbar; überspringe Template-Prüfung"
    return 0
  fi

  local template_name template_storage
  template_name=${RALF_TEMPLATE_PATH##*/}
  template_storage=${RALF_TEMPLATE_PATH%%:*}

  if [[ -z ${template_storage} || ${template_storage} == "${template_name}" ]] || is_placeholder "${template_storage}"; then
    log_warn "Template-Storage konnte nicht bestimmt werden; überspringe Template-Prüfung"
    return 0
  fi

  local output
  if ! output=$(pveam list "${template_storage}" 2>&1); then
    log_error "pveam list ${template_storage} fehlgeschlagen: ${output}"
    return 1
  fi

  if grep -Fq "${template_name}" <<<"${output}"; then
    log_info "Ubuntu-Template ${template_name} verfügbar"
  else
    log_error "Template ${template_name} nicht gefunden"
    return 1
  fi
}

# shellcheck disable=SC2317
check_bridge()
{
  if ip link show "${RALF_BRIDGE}" >/dev/null 2>&1; then
    log_info "Bridge ${RALF_BRIDGE} vorhanden"
  else
    log_error "Bridge ${RALF_BRIDGE} nicht gefunden"
    return 1
  fi
}

# shellcheck disable=SC2317
check_gateway()
{
  if is_placeholder "${RALF_GATEWAY_IPV4:-}"; then
    log_warn "Gateway wurde nicht gesetzt; überspringe Ping"
    return 0
  fi
  if ping -c1 -W2 "${RALF_GATEWAY_IPV4}" >/dev/null 2>&1; then
    log_info "Gateway ${RALF_GATEWAY_IPV4} erreichbar"
  else
    log_error "Gateway ${RALF_GATEWAY_IPV4} nicht erreichbar"
    return 1
  fi
}

# shellcheck disable=SC2317
check_dns()
{
  local resolver=${RALF_DNS_RESOLVER:-1.1.1.1}
  if command -v dig >/dev/null 2>&1; then
    if dig +time=2 +tries=1 @"${resolver}" proxmox.com >/dev/null 2>&1; then
      log_info "DNS-Auflösung via ${resolver} erfolgreich"
    else
      log_error "DNS-Auflösung via ${resolver} fehlgeschlagen"
      return 1
    fi
  else
    if getent hosts proxmox.com >/dev/null 2>&1; then
      log_info "DNS-Auflösung über Systemresolver erfolgreich"
    else
      log_error "DNS-Auflösung fehlgeschlagen"
      return 1
    fi
  fi
}

# shellcheck disable=SC2317
check_ctids()
{
  if [[ ! -f ${IP_SCHEMA} ]]; then
    log_warn "${IP_SCHEMA} nicht gefunden; überspringe CTID-Prüfung"
    return 0
  fi
  local ctids
  mapfile -t ctids < <(grep -E 'ctid:' "${IP_SCHEMA}" | awk '{print $2}' | tr -d '"')
  local conflicts=()
  for ctid in "${ctids[@]}"; do
    if [[ -z ${ctid} || ${ctid} == *ASK_RUNTIME* || ${ctid} == *"\${"* ]]; then
      continue
    fi
    if pct status "${ctid}" >/dev/null 2>&1; then
      conflicts+=("${ctid}")
    fi
  done
  if [[ ${#conflicts[@]} -gt 0 ]]; then
    log_error "CTIDs bereits vergeben: ${conflicts[*]}"
    return 1
  fi
  log_info "CTID-Prüfung erfolgreich"
}

# shellcheck disable=SC2317
check_hostnames()
{
  if [[ ! -f ${IP_SCHEMA} ]]; then
    return 0
  fi
  local hostnames
  mapfile -t hostnames < <(grep -E 'fqdn:' "${IP_SCHEMA}" | awk '{print $2}' | tr -d '"')
  local duplicates
  duplicates=$(printf '%s\n' "${hostnames[@]}" | sort | uniq -d)
  if [[ -n ${duplicates} ]]; then
    log_error "Doppelte FQDN-Einträge: ${duplicates}"
    return 1
  fi
  log_info "FQDN-Konfiguration ohne Duplikate"
}

# shellcheck disable=SC2317
check_time_sync()
{
  if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qiE 'yes|1'; then
    log_info "Zeit-Synchronisation aktiv"
  else
    log_error "NTP-Synchronisation inaktiv"
    return 1
  fi
}

# shellcheck disable=SC2317
check_ssh_keys()
{
  local ssh_dir=${SSH_KEY_DIR:-$HOME/.ssh}
  if [[ -f ${ssh_dir}/id_ed25519.pub ]]; then
    log_info "SSH-Pubkey ${ssh_dir}/id_ed25519.pub gefunden"
    return 0
  fi
  if [[ -f ${ssh_dir}/id_rsa.pub ]]; then
    log_info "SSH-Pubkey ${ssh_dir}/id_rsa.pub gefunden"
    return 0
  fi
  log_error "Kein SSH-Pubkey in ${ssh_dir} gefunden"
  return 1
}

# shellcheck disable=SC2317
check_backup_host()
{
  if is_placeholder "${RALF_BACKUP_HOST:-}"; then
    log_warn "RALF_BACKUP_HOST ist nicht gesetzt; überspringe Backup-Prüfung"
    return 0
  fi
  if is_placeholder "${RALF_BACKUP_PORT:-}"; then
    log_warn "RALF_BACKUP_PORT ist nicht gesetzt; überspringe Backup-Prüfung"
    return 0
  fi
  if command -v nc >/dev/null 2>&1; then
    if nc -z "${RALF_BACKUP_HOST}" "${RALF_BACKUP_PORT}" >/dev/null 2>&1; then
      log_info "Backup-Host ${RALF_BACKUP_HOST}:${RALF_BACKUP_PORT} erreichbar"
    else
      log_error "Backup-Host ${RALF_BACKUP_HOST}:${RALF_BACKUP_PORT} nicht erreichbar"
      return 1
    fi
  else
    log_warn "nc nicht verfügbar; überspringe TCP-Check"
  fi
}

run_check()
{
  local description=$1
  local fn=$2
  if "${fn}"; then
    printf 'PASS: %s\n' "${description}"
    return 0
  fi
  printf 'FAIL: %s\n' "${description}"
  return 1
}

run_checks()
{
  local failures=0
  run_check "Pflichtprogramme verfügbar" check_required_commands || ((failures++))
  run_check "Proxmox Dienste" check_pve_services || ((failures++))
  run_check "Storage vorhanden" check_storage || ((failures++))
  run_check "Template verfügbar" check_template || ((failures++))
  run_check "Bridge vorhanden" check_bridge || ((failures++))
  run_check "Gateway erreichbar" check_gateway || ((failures++))
  run_check "DNS-Auflösung" check_dns || ((failures++))
  run_check "CTIDs frei" check_ctids || ((failures++))
  run_check "FQDN-Validierung" check_hostnames || ((failures++))
  run_check "Zeit-Sync" check_time_sync || ((failures++))
  run_check "SSH-Pubkey" check_ssh_keys || ((failures++))
  run_check "Backup-Host erreichbar" check_backup_host || ((failures++))
  return ${failures}
}

# shellcheck disable=SC2317
check_required_commands()
{
  local -a commands=(pct qm pveversion pvesh lsblk pvesm pveam)
  local missing=""
  local cmd
  for cmd in "${commands[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      if [[ -n ${missing} ]]; then
        missing+=" "
      fi
      missing+="${cmd}"
    fi
  done
  if [[ -n ${missing} ]]; then
    log_error "Pflichtprogramme fehlen: ${missing}"
  local -A checks=(
    ["Pflichtprogramme verfügbar"]="check_required_commands"
    ["Proxmox Dienste"]="check_pve_services"
    ["Storage vorhanden"]="check_storage"
    ["Template verfügbar"]="check_template"
    ["Bridge vorhanden"]="check_bridge"
    ["Gateway erreichbar"]="check_gateway"
    ["DNS-Auflösung"]="check_dns"
    ["CTIDs frei"]="check_ctids"
    ["FQDN-Validierung"]="check_hostnames"
    ["Zeit-Sync"]="check_time_sync"
    ["SSH-Pubkey"]="check_ssh_keys"
    ["Backup-Host erreichbar"]="check_backup_host"
  )

  for description in "${!checks[@]}"; do
    local fn=${checks[${description}]}
    if ${fn}; then
      printf 'PASS: %s\n' "${description}"
    else
      printf 'FAIL: %s\n' "${description}"
      ((failures++))
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Pflichtprogramme fehlen: ${missing[*]}"
    return 1
  fi
  log_info "Alle Pflichtprogramme verfügbar"
}

check_required_commands()
{
  local -a commands=(pct qm pveversion pvesh lsblk)
  local missing=()
  for cmd in "${commands[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Pflichtprogramme fehlen: ${missing[*]}"
    return 1
  fi
  log_info "Alle Pflichtprogramme verfügbar"
}

usage()
{
  cat <<USAGE
Usage: $(basename "$0") [--debug] [--install-proxmox]

Führt Proxmox-Preflight-Checks für das Ralf Homelab aus.
USAGE
}

main()
{
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug)
        DEBUG=1
        ;;
      --install-proxmox)
        INSTALL_PROXMOX=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Unbekannte Option: %s\n' "$1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done

  load_vars
  if ! collect_system_snapshot; then
    log_warn "Systembericht konnte nicht erzeugt werden"
  fi
  if ! ensure_proxmox_available; then
    exit 1
  fi
  if [[ ${PROXMOX_INSTALL_PERFORMED} -eq 1 ]]; then
    REPORT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REPORT_FILE="${REPORT_DIR}/preflight-report-${REPORT_TIMESTAMP}.txt"
    log_info "Erzeuge aktualisierten Systembericht nach Proxmox-Installation"
    if ! collect_system_snapshot; then
      log_warn "Aktualisierter Systembericht konnte nicht erzeugt werden"
    fi
  fi
  if run_checks; then
    log_info "Preflight erfolgreich"
    exit 0
  else
    log_error "Preflight fehlgeschlagen"
    exit 1
  fi
}

main "$@"
