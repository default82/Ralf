#!/usr/bin/env bash
# Minimaler Installer für das Ralf-Grundgerüst.
# Er richtet grundlegende Verzeichnisse, die Standardkonfiguration und logrotate ein.
# Alle Schritte werden explizit ausgegeben, damit das Logging-Narrativ gewahrt bleibt.

set -euo pipefail

log() {
  local message="$1"
  echo "[INSTALL] $message"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "Dieses Skript benötigt Root-Rechte. Bitte mit sudo erneut ausführen."
    exit 1
  fi
}

main() {
  require_root

  local script_dir repo_root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"

  local etc_dir="/etc/ralf"
  local var_log_dir="/var/log/ralf"
  local var_lib_dir="/var/lib/ralf"
  local config_src="${repo_root}/config/default.yml"
  local config_dest="${etc_dir}/config.yml"
  local logrotate_src="${repo_root}/config/logrotate/ralf"
  local logrotate_dest="/etc/logrotate.d/ralf"

  log "Lege benötigte Verzeichnisse an"
  install -d -m 0755 "${etc_dir}"
  install -d -m 0755 "${var_log_dir}"
  install -d -m 0755 "${var_lib_dir}"

  log "Installiere Standardkonfiguration nach ${config_dest}"
  if [[ -f "${config_dest}" ]]; then
    log "Konfigurationsdatei existiert bereits – es wird keine Kopie erstellt"
  else
    install -m 0644 "${config_src}" "${config_dest}"
  fi

  log "Stelle sicher, dass die Systemgruppe 'ralf' vorhanden ist"
  if getent group ralf >/dev/null 2>&1; then
    log "Systemgruppe 'ralf' existiert bereits"
  else
    groupadd --system ralf
    log "Systemgruppe 'ralf' wurde erstellt"
  fi

  log "Stelle sicher, dass der Systembenutzer 'ralf' vorhanden ist"
  if id -u ralf >/dev/null 2>&1; then
    log "Systembenutzer 'ralf' existiert bereits"
  else
    useradd --system \
      --gid ralf \
      --home-dir "${var_lib_dir}" \
      --shell /usr/sbin/nologin \
      --comment "RALF Service Account" \
      ralf
    log "Systembenutzer 'ralf' wurde erstellt"
  fi

  log "Setze Besitzrechte für ${var_log_dir} auf ralf:ralf"
  chown ralf:ralf "${var_log_dir}"

  log "Richte logrotate unter ${logrotate_dest} ein"
  install -m 0644 "${logrotate_src}" "${logrotate_dest}"

  log "Überprüfe Python-Installation"
  if command -v python3 >/dev/null 2>&1; then
    log "Python3 wurde gefunden ($(python3 --version))"
  else
    log "WARNUNG: Python3 wurde nicht gefunden. Bitte installieren, bevor das CLI genutzt wird."
  fi

  log "Basisschritte abgeschlossen. Optional: 'pip install -e .' im Repository ausführen."
}

main "$@"
