#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PATH="${DEFAULT_PATH}:${PATH:-}"

LOG_TAG=${LOG_TAG:-ralf-installer-run}
LOGGER_BIN=$(command -v logger || true)
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
MAKE_BIN=$(command -v make || true)

WITH_GUI=1
SKIP_SMOKE=0
SKIP_BACKUP_CHECK=0

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--no-gui] [--skip-smoke] [--skip-backup-check]

Startet den vollständigen Ralf-Provisionierungsablauf: Preflight, Container-
erstellung sowie Ansible/OpenTofu-Läufe. Standardmäßig wird der grafische
Installer vorab ausgeführt, um Variablen-Dateien zu befüllen.

Optionen:
  --with-gui           Alias für das Standardverhalten (grafischer Installer).
  --no-gui             Überspringt den grafischen Installer und nutzt vorhandene Werte.
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

require_command() {
  local command=$1
  if ! command -v "${command}" >/dev/null 2>&1; then
    log_error "Benötigtes Kommando '${command}' wurde nicht gefunden."
    return 1
  fi
  return 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --with-gui)
      WITH_GUI=1
      ;;
    --no-gui)
      WITH_GUI=0
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
  summary_file="${PROJECT_ROOT}/infra/network/installer-summary.txt"
  if [[ -f ${summary_file} ]]; then
    log_info "Installationsdaten unter ${summary_file} aktualisiert."
  else
    log_warn "Kein Zusammenfassungsdokument ${summary_file} gefunden."
  fi
else
  log_info "Grafischer Installer wird übersprungen. Verwende '--with-gui' für interaktive Eingaben."
fi

if [[ -z ${MAKE_BIN:-} ]]; then
  log_error "make wurde nicht gefunden. Bitte GNU Make bereitstellen (z. B. innerhalb des Management-Containers)."
  exit 1
fi

for required in pct pvesm pveam; do
  require_command "${required}" || exit 1
done

if ! command -v ansible-playbook >/dev/null 2>&1; then
  log_error "ansible-playbook wurde nicht gefunden. Bitte stelle es außerhalb der Proxmox-Host-Umgebung bereit (z. B. im ralf-lxc Container) und starte das Skript erneut."
  exit 1
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
