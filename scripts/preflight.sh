#!/usr/bin/env bash
set -euo pipefail

LOG_TAG=${LOG_TAG:-ralf-preflight}
LOGGER_BIN=$(command -v logger || true)
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VARS_FILE="${PROJECT_ROOT}/infra/network/preflight.vars.source"
IP_SCHEMA="${PROJECT_ROOT}/infra/network/ip-schema.yml"
DEBUG=${DEBUG:-0}

log()
{
  local level=$1; shift
  local message=$*
  [[ -n ${LOGGER_BIN:-} ]] && ${LOGGER_BIN} -t "${LOG_TAG}" "${level}: ${message}" || true
  printf '%s: %s\n' "${level}" "${message}"
}

log_debug() { [[ ${DEBUG} -eq 1 ]] && log "DEBUG" "$*"; }
log_info() { log "INFO" "$*"; }
log_warn() { log "WARN" "$*"; }
log_error() { log "ERROR" "$*"; }

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

check_pve_services()
{
  local services=(${RALF_EXPECTED_PVE_SERVICES:-pvedaemon pveproxy pvestatd})
  local missing=()
  for service in "${services[@]}"; do
    if ! systemctl is-active --quiet "${service}"; then
      missing+=("${service}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Folgende PVE-Dienste sind inaktiv: ${missing[*]}"
    return 1
  fi
  log_info "Alle erwarteten PVE-Dienste sind aktiv"
}

check_storage()
{
  if [[ -z ${RALF_STORAGE_TARGET:-} ]]; then
    log_warn "RALF_STORAGE_TARGET ist nicht gesetzt"
    return 1
  fi
  if pvesm status --storage "${RALF_STORAGE_TARGET}" >/dev/null 2>&1; then
    log_info "Storage ${RALF_STORAGE_TARGET} verfügbar"
  else
    log_error "Storage ${RALF_STORAGE_TARGET} nicht gefunden"
    return 1
  fi
}

check_template()
{
  if [[ -z ${RALF_TEMPLATE_PATH:-} ]]; then
    log_warn "RALF_TEMPLATE_PATH ist nicht gesetzt"
    return 1
  fi
  local template_name
  template_name=${RALF_TEMPLATE_PATH##*/}
  if pveam list | grep -Fq "${template_name}"; then
    log_info "Ubuntu-Template ${template_name} verfügbar"
  else
    log_error "Template ${template_name} nicht gefunden"
    return 1
  fi
}

check_bridge()
{
  if ip link show "${RALF_BRIDGE}" >/dev/null 2>&1; then
    log_info "Bridge ${RALF_BRIDGE} vorhanden"
  else
    log_error "Bridge ${RALF_BRIDGE} nicht gefunden"
    return 1
  fi
}

check_gateway()
{
  if [[ -z ${RALF_GATEWAY_IPV4:-} || ${RALF_GATEWAY_IPV4} == ASK_RUNTIME ]]; then
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
    if [[ -z ${ctid} || ${ctid} == *ASK_RUNTIME* || ${ctid} == *'${'* ]]; then
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
    log_error "Doppelte FQDN-Einträge: ${duplicates}"; return 1
  fi
  log_info "FQDN-Konfiguration ohne Duplikate"
}

check_time_sync()
{
  if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qiE 'yes|1'; then
    log_info "Zeit-Synchronisation aktiv"
  else
    log_error "NTP-Synchronisation inaktiv"
    return 1
  fi
}

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

check_backup_host()
{
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

run_checks()
{
  local failures=0
  local -A checks=(
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
  return ${failures}
}

usage()
{
  cat <<USAGE
Usage: $(basename "$0") [--debug]

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
  if run_checks; then
    log_info "Preflight erfolgreich"
    exit 0
  else
    log_error "Preflight fehlgeschlagen"
    exit 1
  fi
}

main "$@"
