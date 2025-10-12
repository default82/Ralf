#!/usr/bin/env bash
# Ralf Self-Installer
# Lädt das Repository herunter, aktualisiert es bei Bedarf und führt den internen Installer aus.

set -euo pipefail

DEFAULT_REPO_URL="https://github.com/example/ralf.git"
DEFAULT_BRANCH="main"
DEFAULT_TARGET_DIR="/opt/ralf"
LOG_ROOT="/var/log/ralf"
LOG_FILE="${LOG_ROOT}/installer.log"
DRY_RUN=0
REPO_URL="${DEFAULT_REPO_URL}"
BRANCH="${DEFAULT_BRANCH}"
TARGET_DIR="${DEFAULT_TARGET_DIR}"
QUIET_MODE="${RALF_INSTALLER_QUIET:-0}"
TUI_MODE="auto"
TUI_TOOL=""

usage() {
  cat <<'USAGE'
Ralf Self-Installer

Nutzung: install.sh [Optionen]

Optionen:
  --repo-url <url>     Git-URL des Ralf-Repositories (Standard: https://github.com/example/ralf.git)
  --branch <name>      Zu verwendender Git-Branch (Standard: main)
  --target-dir <path>  Zielpfad für das Repository (Standard: /opt/ralf)
  --dry-run            Zeigt nur an, welche Schritte ausgeführt würden
  --tui                Erzwingt den textbasierten Dialog (whiptail/dialog)
  --no-tui             Deaktiviert den textbasierten Dialog explizit
  --quiet              Unterdrückt Konsolenausgaben (Logdatei bleibt aktiv)
  -h, --help           Zeigt diese Hilfe an

Um die Konsolenausgabe zu reduzieren, kann die Variable RALF_INSTALLER_QUIET=1 gesetzt werden.
USAGE
}

log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date --iso-8601=seconds)"
  local line="[${timestamp}] [${level}] ${message}"
  if [[ "${QUIET_MODE}" != "1" ]]; then
    echo "${line}"
  fi
  mkdir -p "${LOG_ROOT}"
  echo "${line}" >> "${LOG_FILE}"
}

trap_error() {
  local exit_code=$?
  local line_no=$1
  if [[ ${exit_code} -ne 0 ]]; then
    log "ERROR" "Abbruch in Zeile ${line_no} (Exit-Code ${exit_code})"
  fi
  exit ${exit_code}
}

trap 'trap_error ${LINENO}' ERR

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "ERROR" "Dieses Skript benötigt Root-Rechte. Bitte mit sudo erneut ausführen."
    exit 1
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log "ERROR" "Benötigtes Kommando '${cmd}' wurde nicht gefunden."
    exit 1
  fi
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-url)
        REPO_URL="$2"
        shift 2
        ;;
      --branch)
        BRANCH="$2"
        shift 2
        ;;
      --target-dir)
        TARGET_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --tui)
        TUI_MODE="force"
        shift
        ;;
      --no-tui)
        TUI_MODE="never"
        shift
        ;;
      --quiet)
        QUIET_MODE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log "ERROR" "Unbekannte Option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

setup_logging() {
  umask 022
  mkdir -p "${LOG_ROOT}"
  if [[ ! -f "${LOG_FILE}" ]]; then
    touch "${LOG_FILE}"
    chmod 0640 "${LOG_FILE}"
  fi
  log "INFO" "Logging initialisiert. Ausgabe wird nach ${LOG_FILE} geschrieben."
}

detect_tui_tool() {
  if command -v whiptail >/dev/null 2>&1; then
    TUI_TOOL="whiptail"
  elif command -v dialog >/dev/null 2>&1; then
    TUI_TOOL="dialog"
  else
    TUI_TOOL=""
  fi
}

run_tui() {
  detect_tui_tool
  if [[ -z "${TUI_TOOL}" ]]; then
    if [[ "${TUI_MODE}" == "force" ]]; then
      log "ERROR" "TUI angefordert, aber weder 'whiptail' noch 'dialog' sind verfügbar."
      exit 1
    fi
    log "INFO" "Kein TUI-Werkzeug gefunden – verwende CLI-Parameter."
    return
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    if [[ "${TUI_MODE}" == "force" ]]; then
      log "ERROR" "TUI angefordert, aber das Skript läuft nicht interaktiv."
      exit 1
    fi
    log "INFO" "Nicht-interaktive Ausführung – TUI wird übersprungen."
    return
  fi

  local backtitle="Ralf Self-Installer"
  log "INFO" "Starte textbasierten Dialog mit ${TUI_TOOL}."

  local repo_input branch_input target_input dry_choice summary

  repo_input=$(tui_input "Git-Repository-URL" "${REPO_URL}" "${backtitle}") || tui_abort
  if [[ -n "${repo_input}" ]]; then
    REPO_URL="${repo_input}"
  fi

  branch_input=$(tui_input "Git-Branch" "${BRANCH}" "${backtitle}") || tui_abort
  if [[ -n "${branch_input}" ]]; then
    BRANCH="${branch_input}"
  fi

  target_input=$(tui_input "Zielpfad für das Repository" "${TARGET_DIR}" "${backtitle}") || tui_abort
  if [[ -n "${target_input}" ]]; then
    TARGET_DIR="${target_input}"
  fi

  dry_choice=$(tui_yesno "Dry-Run ausführen?" "${backtitle}" ${DRY_RUN}) || tui_abort
  if [[ "${dry_choice}" == "yes" ]]; then
    DRY_RUN=1
  else
    DRY_RUN=0
  fi

  summary="Repository: ${REPO_URL}\nBranch: ${BRANCH}\nZielpfad: ${TARGET_DIR}\nDry-Run: $([[ ${DRY_RUN} -eq 1 ]] && echo Ja || echo Nein)"
  tui_message "Bitte bestätigen" "${summary}" "${backtitle}"
  if ! tui_confirm "Konfiguration übernehmen und Installation starten?" "${backtitle}"; then
    tui_abort
  fi

  log "INFO" "TUI-Konfiguration übernommen (Repo=${REPO_URL}, Branch=${BRANCH}, Ziel=${TARGET_DIR}, Dry-Run=${DRY_RUN})."
}

tui_abort() {
  log "INFO" "TUI wurde vom Benutzer abgebrochen."
  exit 0
}

tui_input() {
  local prompt="$1"
  local default="$2"
  local backtitle="$3"
  case "${TUI_TOOL}" in
    whiptail)
      ${TUI_TOOL} --backtitle "${backtitle}" --inputbox "${prompt}" 12 74 "${default}" 3>&1 1>&2 2>&3
      ;;
    dialog)
      ${TUI_TOOL} --backtitle "${backtitle}" --inputbox "${prompt}" 12 74 "${default}" 3>&1 1>&2 2>&3
      ;;
  esac
}

tui_yesno() {
  local prompt="$1"
  local backtitle="$2"
  local current="$3"
  local default_flag=""
  local status
  if [[ "${current}" -eq 0 ]]; then
    default_flag="--defaultno"
  fi
  case "${TUI_TOOL}" in
    whiptail)
      if ${TUI_TOOL} --backtitle "${backtitle}" --yesno "${prompt}" 10 70 ${default_flag}; then
        echo "yes"
        return 0
      fi
      status=$?
      if [[ ${status} -eq 1 ]]; then
        echo "no"
        return 0
      fi
      return 1
      ;;
    dialog)
      if ${TUI_TOOL} --backtitle "${backtitle}" --yesno "${prompt}" 10 70 ${default_flag}; then
        echo "yes"
        return 0
      fi
      status=$?
      if [[ ${status} -eq 1 ]]; then
        echo "no"
        return 0
      fi
      return 1
      ;;
  esac
}

tui_message() {
  local title="$1"
  local message="$2"
  local backtitle="$3"
  case "${TUI_TOOL}" in
    whiptail)
      ${TUI_TOOL} --backtitle "${backtitle}" --title "${title}" --msgbox "${message}" 14 74
      ;;
    dialog)
      ${TUI_TOOL} --backtitle "${backtitle}" --title "${title}" --msgbox "${message}" 14 74
      ;;
  esac
}

tui_confirm() {
  local prompt="$1"
  local backtitle="$2"
  case "${TUI_TOOL}" in
    whiptail)
      ${TUI_TOOL} --backtitle "${backtitle}" --yesno "${prompt}" 10 70
      ;;
    dialog)
      ${TUI_TOOL} --backtitle "${backtitle}" --yesno "${prompt}" 10 70
      ;;
  esac
}

maybe_run_tui() {
  case "${TUI_MODE}" in
    never)
      log "INFO" "TUI durch Option --no-tui deaktiviert."
      return
      ;;
    force)
      run_tui
      return
      ;;
    auto)
      detect_tui_tool
      if [[ -n "${TUI_TOOL}" && -t 0 && -t 1 ]]; then
        run_tui
      else
        if [[ -n "${TUI_TOOL}" ]]; then
          log "INFO" "TUI verfügbar, aber keine interaktive Sitzung erkannt – verwende CLI-Parameter."
        else
          log "INFO" "Kein TUI-Werkzeug gefunden – verwende CLI-Parameter."
        fi
      fi
      ;;
  esac
}

check_prerequisites() {
  require_root
  if [[ ${DRY_RUN} -eq 0 ]]; then
    require_command git
  else
    if ! command -v git >/dev/null 2>&1; then
      log "WARN" "git ist nicht verfügbar. Im Dry-Run wird dies toleriert."
    fi
  fi
}

sync_repository() {
  log "INFO" "Synchronisiere Repository ${REPO_URL} nach ${TARGET_DIR} (Branch: ${BRANCH})."
  if [[ ${DRY_RUN} -eq 1 ]]; then
    log "INFO" "Dry-Run aktiv – git clone/pull wird übersprungen."
    return
  fi

  mkdir -p "$(dirname "${TARGET_DIR}")"
  if [[ -d "${TARGET_DIR}/.git" ]]; then
    log "INFO" "Bestehendes Repository gefunden – führe Update aus."
    git -C "${TARGET_DIR}" fetch --all --prune
    git -C "${TARGET_DIR}" checkout "${BRANCH}"
    git -C "${TARGET_DIR}" pull --ff-only origin "${BRANCH}"
  else
    log "INFO" "Klone Repository neu."
    git clone --branch "${BRANCH}" "${REPO_URL}" "${TARGET_DIR}"
  fi
}

run_internal_installer() {
  local installer="${TARGET_DIR}/scripts/install.sh"
  if [[ ${DRY_RUN} -eq 1 ]]; then
    log "INFO" "Dry-Run aktiv – interner Installer wird nicht ausgeführt (${installer})."
    return
  fi

  if [[ ! -f "${installer}" ]]; then
    log "ERROR" "Interner Installer ${installer} nicht gefunden."
    exit 1
  fi

  log "INFO" "Starte internen Installer ${installer}."
  bash "${installer}"
}

main() {
  parse_arguments "$@"
  setup_logging
  log "INFO" "Starte Ralf Self-Installer"
  maybe_run_tui
  log "INFO" "Parameter: repo_url=${REPO_URL}, branch=${BRANCH}, target_dir=${TARGET_DIR}, dry_run=${DRY_RUN}"
  check_prerequisites
  sync_repository
  run_internal_installer
  log "INFO" "Installation abgeschlossen."
}

main "$@"
