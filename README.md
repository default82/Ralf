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

## Offene Aufgaben

Der aktuelle Arbeitsstand wird hier zusammengefasst; Details und Fortschrittspflege erfolgen zusätzlich in `docs/TODO.md`.

### Kurzfristig

- [ ] Werte in `infra/network/ip-schema.yml` gemäß aktueller Netzplanung ergänzen.
- [ ] `infra/network/preflight.vars.source` mit Proxmox-Storage, Template-Namen und Netzwerkparametern füllen.
- [ ] age-Recipient in `secrets/.sops.yaml` eintragen und Schlüssel bereitstellen.
- [ ] Secrets in `ansible/group_vars/all/*.enc.yml` mit SOPS verschlüsselt pflegen.
- [ ] Ressourcenprofile (CPU/RAM/Disk) in den `scripts/pct-create-*.sh` Skripten überprüfen und bei Bedarf anpassen.

### Mittelfristig

- [ ] OpenTofu-Module unter `infra/` ergänzen (Netzwerk, DNS, Storage-Automatisierung).
- [ ] CI-Pipeline für `make lint` und `make validate` aufbauen.
- [ ] Zusätzliche Smoke-Checks für Foreman API und n8n Workflows implementieren.
- [ ] Logrotate-Konfiguration um Foreman-/n8n-spezifische Logs erweitern.

### Langfristig

- [ ] Integration weiterer Dienste (z. B. Monitoring-Stack) evaluieren.
- [ ] Disaster-Recovery-Pläne dokumentieren und testen.
- [ ] Automatisiertes Patch-Management über Foreman/Satellite prüfen.

## How-to-Run

```bash
make preflight
./scripts/pct-create-ralf.sh
./scripts/pct-create-svc-postgres.sh
./scripts/pct-create-svc-semaphore.sh
./scripts/pct-create-svc-foreman.sh
./scripts/pct-create-svc-n8n.sh
./scripts/pct-create-svc-vaultwarden.sh
make plan && make apply
make smoke
make backup-check
```

Weitere Details zu Sequenzen, Variablen und Service-Workflows findest du in `docs/SETUP.md` und `docs/ARCHITECTURE.md`.
