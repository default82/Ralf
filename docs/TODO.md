# Aufgabenübersicht

## Kurzfristig
- [ ] Werte in `infra/network/ip-schema.yml` gemäß aktueller Netzplanung ergänzen.
- [ ] `infra/network/preflight.vars.source` mit Proxmox-Storage, Template-Namen und Netzwerkparametern füllen.
- [ ] age-Recipient in `secrets/.sops.yaml` eintragen und Schlüssel bereitstellen.
- [ ] Secrets in `ansible/group_vars/all/*.enc.yml` mit SOPS verschlüsselt pflegen.
- [ ] Ressourcenprofile (CPU/RAM/Disk) in den `scripts/pct-create-*.sh` Skripten überprüfen und bei Bedarf anpassen.
- [ ] Grafischen Installer (`make install`) mit produktiven Werten befüllen und Ergebnisse prüfen.

## Mittelfristig
- [ ] OpenTofu-Module unter `infra/` ergänzen (Netzwerk, DNS, Storage-Automatisierung).
- [ ] CI-Pipeline für `make lint` und `make validate` aufbauen.
- [ ] Zusätzliche Smoke-Checks für Foreman API und n8n Workflows implementieren.
- [ ] Logrotate-Konfiguration um Foreman-/n8n-spezifische Logs erweitern.

## Langfristig
- [ ] Integration weiterer Dienste (z. B. Monitoring-Stack) evaluieren.
- [ ] Disaster-Recovery-Pläne dokumentieren und testen.
- [ ] Automatisiertes Patch-Management über Foreman/Satellite prüfen.

