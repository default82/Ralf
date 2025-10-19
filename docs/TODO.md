# Aufgabenübersicht

## Kurzfristig
- [x] Orchestrierendes Installationsskript (`scripts/install.sh`) bereitstellen.
  - [x] Argument-Parsing für GUI-, Smoke- und Backup-Flags implementieren.
  - [x] Schrittweises Logging via `logger`/STDOUT sicherstellen.
  - [x] `make plan`, `make apply`, `make smoke` und `make backup-check` als Subkommandos anbinden.
- [ ] Werte in `infra/network/ip-schema.yml` gemäß aktueller Netzplanung ergänzen.
  - [ ] Endgültiges CTID-/Subnetz-Schema aus der Ralf-Netzplanung ableiten und schriftlich festhalten.
  - [ ] Platzhalter (`${VAR}`/Defaults) in feste IPv4-, Gateway- und FQDN-Werte umwandeln.
  - [ ] Mit `yq eval '.[]|{ctid,ipv4,fqdn}' infra/network/ip-schema.yml` querprüfen, dass keine `ASK_RUNTIME`-Werte verbleiben.
- [ ] `infra/network/preflight.vars.source` mit Proxmox-Storage, Template-Namen und Netzwerkparametern füllen.
  - [ ] Produktives Storage-Target (`pvesm status`) und Template-Pfad (`pveam available`) recherchieren und hinterlegen.
  - [ ] Bridge, DNS-Resolver, Gateway und Backup-Endpunkt aus der Infrastruktur-Doku übernehmen.
  - [ ] Container-Ressourcen (CTID, vCPU, RAM, Disk) gemäß Tabelle in `docs/SETUP.md` abgleichen.
  - [ ] `scripts/preflight.sh` einmal mit gesetzten Variablen ausführen und prüfen, dass keine interaktiven Prompts erscheinen.
- [x] age-Recipient in `secrets/.sops.yaml` eintragen und Schlüssel bereitstellen.
  - [x] `age1dhl426f…` als Empfänger in den Creation-Rules hinterlegen.
  - [x] Speicherort des privaten Keys (`secrets/keys/ralf-age-key.txt`) dokumentieren.
- [x] Secrets in `ansible/group_vars/all/*.enc.yml` mit SOPS verschlüsselt pflegen.
  - [x] Datenbank-Credentials für Postgres-Admin und Applikationen einpflegen.
  - [x] Applikations-Secrets (Semaphore, n8n, Vaultwarden) aktualisieren und re-verschlüsseln.
  - [ ] `ansible-playbook --check ansible/playbooks/site.yml` mit gesetzten Secrets laufen lassen und Ergebnis dokumentieren.
- [x] Ressourcenprofile (CPU/RAM/Disk) in den `scripts/pct-create-*.sh` Skripten überprüfen, Zielwerte dokumentieren und Defaults anpassen (`docs/SETUP.md`).
  - [x] Default-Ressourcen in jedem `pct-create-*.sh` Skript auf Hostkapazitäten abstimmen.
  - [x] Tabelle mit Zielwerten in `docs/SETUP.md` ergänzen.
  - [ ] Stichprobenlauf (`scripts/pct-create-svc-postgres.sh` o. ä.) mit gesetzten Variablen durchführen und Output archivieren.
- [ ] Dokumentationsduplikate in README/SETUP bereinigen.
  - [ ] Doppelte `preflight`-Tabelleneinträge und redundante Absätze in `README.md` entfernen.
  - [ ] Wiederholte Schrittfolgen in `docs/SETUP.md` zusammenführen.
  - [ ] Querverweise (z. B. `docs/TODO.md`, `docs/SETUP.md`) nach der Bereinigung prüfen.

## Mittelfristig
- [ ] OpenTofu-Module unter `infra/` ergänzen (Netzwerk, DNS, Storage-Automatisierung).
  - [ ] Modulstruktur (`infra/tofu/main.tf`, `variables.tf`, `outputs.tf`) anlegen.
  - [ ] Ressourcen für Netzwerk, DNS und Storage modellieren und mit Platzhalterwerten versehen.
  - [ ] `make plan` gegen ein Test-Backend laufen lassen und State-Dateien versionieren.
- [ ] CI-Pipeline für `make lint` und `make validate` aufbauen.
  - [ ] GitHub Actions oder vergleichbare Pipeline-Datei (`.github/workflows/ci.yml`) erstellen.
  - [ ] Jobs für Shell-Lint (`shellcheck`), Ansible-Lint und YAML-Lint hinzufügen.
  - [ ] Artefakte/Logs der Pipeline in `docs/CI.md` oder README verlinken.
- [ ] Zusätzliche Smoke-Checks für Foreman API und n8n Workflows implementieren.
  - [ ] Endpunkt-Spezifikation (URLs, erwartete Statuscodes) zusammentragen.
  - [ ] `scripts/smoke.sh` um neue Funktionen erweitern und Tests dokumentieren.
  - [ ] Ergebnisse in `logs/smoke-*.txt` auswerten und im README erwähnen.
- [ ] Logrotate-Konfiguration um Foreman-/n8n-spezifische Logs erweitern.
  - [ ] Logpfade der Dienste identifizieren (z. B. `/var/log/foreman/production.log`).
  - [ ] Neue Regeln in `ansible/roles/common/templates/logrotate.d/` hinzufügen.
  - [ ] `logrotate --debug` auf einem Testsystem ausführen und Output ablegen.

## Langfristig
- [ ] Integration weiterer Dienste (z. B. Monitoring-Stack) evaluieren.
  - [ ] Anforderungskatalog (Metriken, Alerts) erstellen und in `docs/ARCHITECTURE.md` aufnehmen.
  - [ ] Proof-of-Concept für Prometheus/Grafana oder Alternativen durchführen.
  - [ ] Entscheidungsvorlage mit Ressourcenbedarf und Betriebskonzept verfassen.
- [ ] Disaster-Recovery-Pläne dokumentieren und testen.
  - [ ] Kritische Wiederherstellungs-Szenarien identifizieren (z. B. Verlust von `svc-postgres`).
  - [ ] Wiederanlauf-Handbuch in `docs/DR.md` anlegen und halbjährliche Testtermine planen.
  - [ ] Ergebnisse der Restore-Tests versionieren (Protokolle unter `docs/reports/`).
- [ ] Automatisiertes Patch-Management über Foreman/Satellite prüfen.
  - [ ] Foreman-Kapazitäten und Plugin-Landschaft evaluieren.
  - [ ] Pilot-Rollout auf einem Test-Host durchführen und Compliance-Reports sammeln.
  - [ ] Betriebsleitfaden inkl. Wartungsfenster in `docs/OPERATIONS.md` dokumentieren.

