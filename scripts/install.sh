#!/usr/bin/env bash
set -euo pipefail

LOG_TAG=${LOG_TAG:-ralf-installer-run}
LOGGER_BIN=$(command -v logger || true)
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
MAKE_BIN=$(command -v make || true)
APT_GET_BIN=$(command -v apt-get || command -v apt || true)
APT_UPDATED=0

WITH_GUI=0
SKIP_SMOKE=0
SKIP_BACKUP_CHECK=0

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--with-gui] [--skip-smoke] [--skip-backup-check]

Startet den vollständigen Ralf-Provisionierungsablauf: Preflight, Container-
erstellung sowie Ansible/OpenTofu-Läufe. Optional kann der grafische Installer
vorab ausgeführt werden, um Variablen-Dateien zu befüllen.

Optionen:
  --with-gui           Führt vor dem Preflight den Dialog-basierten Installer aus.
  --skip-smoke         Überspringt abschließende Smoke-Tests.
  --skip-backup-check  Überspringt die Borgmatic-Validierung.
  -h, --help           Zeigt diese Hilfe an.
USAGE
}

log() {
  local level=$1; shift
  local message=$*
  [[ -n ${LOGGER_BIN:-} ]] && ${LOGGER_BIN} -t "${LOG_TAG}" "${level}: ${message}" || true
  printf '%s: %s\n' "${level}" "${message}"
}

log_info() { log "INFO" "$*"; }
log_warn() { log "WARN" "$*"; }
log_error() { log "ERROR" "$*"; }

ensure_package() {
  local package=$1
  if [[ -z ${APT_GET_BIN:-} ]]; then
    return 1
  fi
  if (( APT_UPDATED == 0 )); then
    log_info "Aktualisiere Paketquellen (apt update)"
    DEBIAN_FRONTEND=noninteractive "${APT_GET_BIN}" update
    APT_UPDATED=1
  fi
  log_info "Installiere Paket '${package}'"
  if DEBIAN_FRONTEND=noninteractive "${APT_GET_BIN}" install -y "${package}"; then
    return 0
  fi
  return 1
}

ensure_command() {
  local command=$1
  shift || true
  local packages=("$@")
  if command -v "${command}" >/dev/null 2>&1; then
    return 0
  fi
  for pkg in "${packages[@]}"; do
    if ensure_package "${pkg}" && command -v "${command}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --with-gui)
      WITH_GUI=1
      ;;
    --skip-smoke)
      SKIP_SMOKE=1
      ;;
    --skip-backup-check)
      SKIP_BACKUP_CHECK=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unbekannte Option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  log_error "Dieses Skript muss als root ausgeführt werden."
  exit 1
fi

if [[ -z ${MAKE_BIN:-} ]]; then
  log_error "make wurde nicht gefunden. Bitte GNU Make installieren."
  exit 1
fi

for required in pct pvesm pveam; do
  if ! command -v "${required}" >/dev/null 2>&1; then
    log_error "Benötigtes Kommando '${required}' wurde nicht gefunden."
    exit 1
  fi
done

if ! ensure_command ansible-playbook ansible-core ansible; then
  log_error "ansible-playbook wurde nicht gefunden und konnte nicht automatisch installiert werden."
  exit 1
fi

assert_executable() {
  local path=$1
  if [[ ! -x ${path} ]]; then
    log_error "Skript ${path} ist nicht ausführbar."
    exit 1
  fi
}

CURRENT_STEP=""
on_error() {
  local exit_code=$?
  log_error "Installation bei Schritt '${CURRENT_STEP:-unbekannt}' fehlgeschlagen (Exit-Code ${exit_code})."
  exit "${exit_code}"
}

trap on_error ERR

run_step() {
  local description=$1
  shift
  local -a cmd=("$@")
  CURRENT_STEP="${description}"
  log_info "Starte: ${description}"
  (cd "${PROJECT_ROOT}" && "${cmd[@]}")
  log_info "Abgeschlossen: ${description}"
}

if (( WITH_GUI )); then
  local_gui="${SCRIPTS_DIR}/install-gui.sh"
  assert_executable "${local_gui}"
  if ! command -v whiptail >/dev/null 2>&1 && ! command -v dialog >/dev/null 2>&1; then
    log_error "Grafischer Installer angefordert, aber weder whiptail noch dialog sind installiert."
    exit 1
  fi
  run_step "Grafischer Installer" "${local_gui}"
else
  log_info "Grafischer Installer wird übersprungen. Verwende '--with-gui' für interaktive Eingaben."
fi

assert_executable "${SCRIPTS_DIR}/preflight.sh"
run_step "Preflight-Checks" "${SCRIPTS_DIR}/preflight.sh"

container_scripts=(
  "ralf-lxc|${SCRIPTS_DIR}/pct-create-ralf.sh"
  "svc-postgres|${SCRIPTS_DIR}/pct-create-svc-postgres.sh"
  "svc-semaphore|${SCRIPTS_DIR}/pct-create-svc-semaphore.sh"
  "svc-foreman|${SCRIPTS_DIR}/pct-create-svc-foreman.sh"
  "svc-n8n|${SCRIPTS_DIR}/pct-create-svc-n8n.sh"
  "svc-vaultwarden|${SCRIPTS_DIR}/pct-create-svc-vaultwarden.sh"
)

for entry in "${container_scripts[@]}"; do
  IFS='|' read -r name path <<<"${entry}"
  assert_executable "${path}"
  run_step "Container-Provisionierung ${name}" "${path}"
done

if [[ -z ${SOPS_AGE_KEY_FILE:-} ]]; then
  log_warn "SOPS_AGE_KEY_FILE ist nicht gesetzt. Ansible könnte Secrets nicht entschlüsseln."
fi

run_step "Plan-Lauf (OpenTofu/Ansible)" "${MAKE_BIN}" plan
run_step "Apply-Lauf (OpenTofu/Ansible)" "${MAKE_BIN}" apply

if (( SKIP_SMOKE )); then
  log_warn "Smoke-Tests wurden explizit übersprungen."
else
  run_step "Smoke-Tests" "${MAKE_BIN}" smoke
fi

if (( SKIP_BACKUP_CHECK )); then
  log_warn "Backup-Validierung wurde explizit übersprungen."
else
  run_step "Borgmatic-Validierung" "${MAKE_BIN}" backup-check
fi

log_info "Installation erfolgreich abgeschlossen."
