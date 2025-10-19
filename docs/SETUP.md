# Setup-Anleitung für R.A.L.F.

Diese Anleitung führt durch den kompletten Lebenszyklus des Homelab-Gerüsts. Alle Entscheidungen zu CTIDs, IP-Adressen, Speicher und Secrets triffst du zur Laufzeit. Stelle sicher, dass `RALF-lxc-bootstrap-v5.1/README.md` parallel konsultiert wird – dort findest du historische Besonderheiten, die weiterhin gelten.

## Voraussetzungen

- Proxmox VE Host (`pve01`) mit unprivilegierten LXC-Containern und `nesting=1`. Auf einem frischen Debian-Host installierst du Proxmox automatisch über `scripts/preflight.sh --install-proxmox`.
- Ubuntu 24.04 Standard-Template im Proxmox-Storage (`local:vztmpl/ubuntu-24.04-standard_*.tar.zst`) – der genaue Name wird zur Laufzeit über Variablen gesetzt.
- SSH-Schlüssel-basierte Authentifizierung; Passwort-Login ist deaktiviert.
- Zugang zu einem externen Backup-Host (Borgmatic via SSH/22).

## Variablen & Struktur

1. **Netzwerk:** Pflege `infra/network/ip-schema.yml` mit Hostnamen, FQDNs und Platzhalter-Variablen.
2. **Preflight-Vars:** Ergänze `infra/network/preflight.vars.source`. Die Datei wird von `scripts/preflight.sh` geladen.
3. **Secrets:** Entschlüssele und bearbeite die Dateien unter `ansible/group_vars/all/*.enc.yml` mit SOPS. Füge deinen age-Recipient zur Laufzeit in `secrets/.sops.yaml` ein.

## Provisionierungsablauf

Vor dem ersten Lauf: Klone dieses Repository nach `/opt/ralf` auf `ralf-lxc` oder passe `ralf_cli_make_path` in den Variablen an.

### Vollautomatischer Durchlauf

Nutze `./scripts/install.sh` für einen end-to-end Lauf inklusive Preflight, Container-Provisionierung sowie `make plan/apply` und nachgelagerter Prüfungen. Mit `--with-gui` startet vorab der dialog-basierte Installer (`scripts/install-gui.sh` – benötigt das Paket `dialog`). Dieser erfasst die Variablen aus `infra/network/preflight.vars.source` und `infra/network/ip-schema.yml` und öffnet im Anschluss einen mausbedienbaren Preflight-Dashboard, das jede Prüfung aus `scripts/preflight.sh` inklusive Handlungsempfehlungen durchgeht. Optional lassen sich Smoke- bzw. Backup-Checks mit `--skip-smoke` bzw. `--skip-backup-check` ausblenden.

### Manuelle Sequenz

1. Führe `make preflight` auf `pve01` aus. Das Skript prüft Proxmox-Dienste, Storage, Netz und SSH-Voraussetzungen und legt einen Bericht unter `logs/preflight-report-<timestamp>.txt` (über `RALF_PREFLIGHT_REPORT_DIR` überschreibbar) ab. Falls Proxmox noch nicht installiert ist, nutze `scripts/preflight.sh --install-proxmox` direkt auf dem Host und wiederhole anschließend den Preflight.
1. Führe `make preflight` auf `pve01` aus. Das Skript prüft Proxmox-Dienste, Storage, Netz und SSH-Voraussetzungen und legt einen Bericht unter `logs/preflight-report-<timestamp>.txt` (über `RALF_PREFLIGHT_REPORT_DIR` überschreibbar) ab.
2. Erstelle die LXC-Container mit den `scripts/pct-create-*.sh` Skripten in der angegebenen Reihenfolge. Sie lesen Variablen aus `infra/network/` und fragen bei Bedarf CTIDs, Ressourcen und IPs interaktiv ab.
3. Setze `export SOPS_AGE_KEY_FILE=/pfad/zum/key` und stelle sicher, dass SOPS Zugriff auf deine age-Identität hat.
4. Führe `make plan` gefolgt von `make apply` aus `ralf-lxc` aus. `make plan` beinhaltet `terraform plan`/`tofu plan` (sobald Module vorhanden sind) und `ansible-playbook --check` Läufe. `make apply` startet `tofu apply` gefolgt von `ansible-playbook` Runs.
5. Nach erfolgreicher Provisionierung führe `make smoke` für die Endpunkt-Checks und `make backup-check` zur Validierung der Borgmatic-Jobs aus.

## Ansible Playbooks

- `ansible/playbooks/site.yml`: orchestriert alle Rollen entsprechend der Gruppen `mgmt`, `db`, `apps`.
- `ansible/playbooks/mgmt.yml`: fokussiert `ralf-lxc` (Control Plane).
- `ansible/playbooks/db.yml`: richtet PostgreSQL inklusive DBs und Benutzer ein.
- `ansible/playbooks/apps.yml`: konfiguriert Semaphore, Foreman, n8n und Vaultwarden.

Alle Playbooks sind idempotent ausgelegt. Ein zweiter Lauf muss `changed=0` ergeben, sofern keine Änderungen vorgenommen wurden.

## Logging & Monitoring

- Skripte verwenden `logger -t ralf-preflight` bzw. ähnliche Tags.
- Ansible-Rollen schreiben Logfiles nach `/var/log/ralf/`. Stelle sicher, dass Logrotate entsprechend erweitert wird (siehe Rolle `common`).
- Smoke-Checks befinden sich in `scripts/smoke.sh` und nutzen HTTP- und TCP-Prüfungen.

## Backup-Konzept

- Borgmatic läuft auf allen stateful Hosts (`svc-postgres`, `svc-foreman`, `svc-n8n`, `svc-vaultwarden` und optional `svc-semaphore`).
- Retention: 7 Daily, 4 Weekly, 6 Monthly. Diese Werte kannst du bei Bedarf in `ansible/roles/borgmatic/defaults/main.yml` anpassen.
- `make backup-check` triggert `borgmatic --check --extract` mit Restore-Probe nach `/tmp/restore`.

## Fehlerbehebung

- `scripts/preflight.sh --debug` zeigt zusätzliche Diagnoseinformationen.
- Nutze `ralfctl logs <service>` um journald-Logs gezielt auszulesen (wird durch die Rolle `ralf_cli` bereitgestellt).
- Für wiederholbare Tests empfiehlt sich ein Snapshot der LXC-Container vor dem Ansible-Lauf.

