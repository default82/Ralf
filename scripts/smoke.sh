#!/usr/bin/env bash
set -euo pipefail

LOG_TAG=${LOG_TAG:-ralf-smoke}
LOGGER_BIN=$(command -v logger || true)
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY:-${PROJECT_ROOT}/ansible/inventories/home/hosts.yml}
CURL_BIN=${CURL_BIN:-curl}
ANSIBLE_BIN=${ANSIBLE_BIN:-ansible}
POSTGRES_HOST=${POSTGRES_HOST:-svc-postgres.home.arpa}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
SEMAPHORE_URL=${SEMAPHORE_URL:-https://svc-semaphore.home.arpa}
FOREMAN_URL=${FOREMAN_URL:-https://svc-foreman.home.arpa}
N8N_URL=${N8N_URL:-https://svc-n8n.home.arpa}
VAULTWARDEN_URL=${VAULTWARDEN_URL:-https://svc-vaultwarden.home.arpa/admin}

log()
{
  local level=$1; shift
  local message=$*
  [[ -n ${LOGGER_BIN:-} ]] && ${LOGGER_BIN} -t "${LOG_TAG}" "${level}: ${message}" || true
  printf '%s: %s\n' "${level}" "${message}"
}

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; }

check_systemd()
{
  local host=$1 service=$2 label=$3
  if ${ANSIBLE_BIN} -i "${ANSIBLE_INVENTORY}" "${host}" -m ansible.builtin.command -a "systemctl is-active --quiet ${service}" >/dev/null; then
    pass "${label:-${host} ${service}}"
    log "INFO" "${host}: ${service} aktiv"
    return 0
  else
    fail "${label:-${host} ${service}}"
    log "ERROR" "${host}: ${service} nicht aktiv"
    return 1
  fi
}

check_http()
{
  local url=$1 expect=$2 label=$3
  local status
  status=$(${CURL_BIN} -fksS -o /dev/null -w '%{http_code}' --max-time 5 "${url}" || true)
  if [[ -z ${status} ]]; then
    status="000"
  fi
  if [[ ${status} == ${expect} ]]; then
    pass "${label:-${url}}"
    log "INFO" "HTTP-Check ${url} erfolgreich (${status})"
    return 0
  else
    fail "${label:-${url}}"
    log "ERROR" "HTTP-Check ${url} -> ${status}, erwartet ${expect}"
    return 1
  fi
}

check_psql()
{
  local label="PostgreSQL select 1"
  if [[ -z ${PGPASSWORD:-} && ! -f "$HOME/.pgpass" ]]; then
    log "WARN" "PGPASSWORD/.pgpass nicht gesetzt; überspringe ${label}"
    pass "${label} (übersprungen)"
    return 0
  fi
  if PGPASSWORD=${PGPASSWORD:-${PGPASS:-}} psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc 'select 1' >/dev/null 2>&1; then
    pass "${label}"
    log "INFO" "psql select 1 erfolgreich"
    return 0
  else
    fail "${label}"
    log "ERROR" "psql select 1 fehlgeschlagen"
    return 1
  fi
}

main()
{
  local failures=0

  check_systemd ralf-lxc borgmatic "ralf-lxc borgmatic" || ((failures++))
  check_systemd svc-postgres postgresql "svc-postgres postgresql" || ((failures++))
  check_systemd svc-semaphore semaphore "svc-semaphore semaphore" || ((failures++))
  check_systemd svc-foreman foreman "svc-foreman foreman" || ((failures++))
  check_systemd svc-n8n n8n "svc-n8n n8n" || ((failures++))
  check_systemd svc-vaultwarden vaultwarden "svc-vaultwarden vaultwarden" || ((failures++))

  check_psql || ((failures++))

  check_http "${SEMAPHORE_URL}/api/info" 200 "Semaphore API" || ((failures++))
  check_http "${FOREMAN_URL}" 200 "Foreman UI" || ((failures++))
  check_http "${N8N_URL}/healthz" 200 "n8n Health" || ((failures++))
  check_http "${VAULTWARDEN_URL}" 401 "Vaultwarden Admin" || ((failures++))

  if [[ ${failures} -eq 0 ]]; then
    log "INFO" "Alle Smoke-Checks erfolgreich"
    exit 0
  else
    log "ERROR" "${failures} Smoke-Checks fehlgeschlagen"
    exit 1
  fi
}

main "$@"
