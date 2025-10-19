# R.A.L.F. Homelab Control Stack

Ralf (Reliable Autonomous Lab Fabric) stellt ein reproduzierbares Grundgerüst für ein Proxmox-basiertes Homelab bereit. Das Repository bündelt Container-Provisionierung, Konfigurationsmanagement und Betriebsroutinen, damit ein kompletter Neuaufbau deterministisch und auditierbar bleibt.

> **Hinweis:** Ergänzende Setup-Details findest du in `RALF-lxc-bootstrap-v5.1/README.md`. Diese Referenz beschreibt historische Bootstrap-Schritte und bleibt maßgeblich für tiefergehende Installationshinweise.

## Repository-Layout

```
.
├── ansible/                # Inventare, Playbooks und Rollen für alle LXC-Hosts
├── docs/                   # Architektur, Setup-Anleitungen und Aufgabenliste
├── infra/                  # statische Netzinformationen und Proxmox-Vars
├── scripts/                # Preflight-, pct-Create- und Smoke-Skripte
├── secrets/                # SOPS-Konfiguration und verschlüsselte Variablen-Dateien
├── Makefile                # zentrale Workflows (lint, plan, apply, smoke, backup)
├── .pre-commit-config.yaml # statische Analysen und Linting
└── .editorconfig           # einheitliche Formatierungsrichtlinien
```

Jeder Host und Dienst bleibt über Variablen konfigurierbar. Entscheidungen zu CTIDs, IP-Adressen, Speicherzielen und age-Recipients erfolgen konsequent zur Laufzeit über Variablen-Dateien oder Interaktion mit `ralfctl`.

## Kernkomponenten

| Kategorie      | Dienst            | Zweck                                                                 |
| -------------- | ----------------- | --------------------------------------------------------------------- |
| Control Plane  | `ralf-lxc`        | Ansible, OpenTofu, SOPS/age, Borgmatic, Ralf-CLI                      |
| Datenhaltung   | `svc-postgres`    | PostgreSQL 16 für Foreman, Semaphore, n8n und optional Vaultwarden    |
| Automatisierung| `svc-semaphore`   | Web-GUI zur Ansible-Orchestrierung                                    |
| Lifecycle      | `svc-foreman`     | Foreman Core zur Systemverwaltung (ohne Katello)                      |
| Automation     | `svc-n8n`         | Workflow-Automatisierung, nutzt zentrale PostgreSQL-Instanz          |
| Secrets        | `svc-vaultwarden` | Passwortverwaltung, standardmäßig auf PostgreSQL geschaltet          |

Alle stateful Komponenten besitzen dedizierte Borgmatic-Backups. Smoke-Checks stellen nach jeder Provisionierung die Erreichbarkeit und Grundfunktion sicher.

## Workflows

### Makefile-Targets

| Target        | Beschreibung                                                                 |
| ------------- | ----------------------------------------------------------------------------- |
| `lint`        | Führt Pre-Commit-Hooks und statische Analysen auf Skripten und Playbooks aus. |
| `validate`    | Validiert OpenTofu/Ansible-Konfigurationen ohne Änderungen.                   |
| `preflight`   | Führt `scripts/preflight.sh` auf dem Proxmox-Host aus.                        |
| `plan`        | Erstellt Ausführungspläne (OpenTofu, Ansible Check-Mode).                     |
| `apply`       | Wendet Infrastruktur- und Konfigurationsänderungen an.                        |
| `smoke`       | Prüft Dienste über `scripts/smoke.sh`.                                        |
| `backup-check`| Validiert Borgmatic-Backups inkl. Restore-Probe.                              |

`ralfctl` fungiert als CLI-Wrapper und delegiert die Make-Targets für eine einheitliche Nutzererfahrung.

## Secrets & Compliance

Sämtliche sensitiven Werte liegen verschlüsselt unter `secrets/` bzw. `ansible/group_vars/all/*.enc.yml` (SOPS + age). Der age-Recipient wird erst zur Laufzeit gepflegt; verwende `export SOPS_AGE_KEY_FILE=/pfad/zum/key` bevor du `make apply` ausführst.

## Monitoring & Backups

- **Borgmatic:** Auf allen stateful LXC-Containern aktiviert, inkl. Restore-Test nach jedem Lauf.
- **Smoke-Checks:** HTTP-Statusprüfungen, `psql`-Connectivity sowie Systemd-Statuskontrollen.
- **Logging:** Skripte nutzen `logger`, Rollen schreiben strukturierte Logs unter `/var/log/ralf/` (siehe `docs/SETUP.md`).

## How-to-Run

Für einen vollautomatisierten Erstaufbau steht ein orchestrierendes Skript bereit:

```bash
sudo ./scripts/install.sh
```

Führe das Skript auf dem Proxmox-Host als `root` aus. Der grafische Installer (`scripts/install-gui.sh`) wird automatisch als erster Schritt gestartet, sammelt alle benötigten Netzwerk- und Infrastrukturwerte und legt eine Zusammenfassung unter `infra/network/installer-summary.txt` ab. Das Skript erwartet, dass benötigte Werkzeuge wie `ansible-playbook` bereits in einer Management-Umgebung (z. B. innerhalb des `ralf-lxc` Containers) zur Verfügung stehen – auf dem Proxmox-Host werden keine zusätzlichen Pakete installiert. Weitere Schalter (`--no-gui`, `--skip-smoke`, `--skip-backup-check`) erlauben es, einzelne Phasen bewusst auszulassen.

Wer die Schritte granular abarbeiten möchte, findet die Einzelkommandos weiterhin in `docs/SETUP.md`. Dort sowie in `docs/ARCHITECTURE.md` sind zusätzliche Details zu Sequenzen, Variablen und Service-Workflows beschrieben.
