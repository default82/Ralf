# Offene Punkte im RALF-Repository

Diese Datei sammelt aktuelle TODO-Einträge und offene Aufgaben, die in der Codebasis dokumentiert sind.

## Portal
- [ ] UI-Build-Pipeline implementieren (`portal/README.md`).
- [ ] Servicekatalog-Schema definieren (`portal/README.md`).
- [ ] Authentifizierungsintegration (Keycloak/Authelia) umsetzen (`portal/README.md`).

## Ansible-Rollen
Die folgenden Rollen benötigen jeweils eine vollständige Ausarbeitung der Standard-Variablen, Tasks und zugehörigen Handler/Templates:
- monitoring (`ansible/roles/monitoring/README.md`)
- dns (`ansible/roles/dns/README.md`)
- auth (`ansible/roles/auth/README.md`)
- homeassistant (`ansible/roles/homeassistant/README.md`)
- caddy (`ansible/roles/caddy/README.md`)
- backups (`ansible/roles/backups/README.md`)

✅ Erledigt:
- base (`ansible/roles/base/README.md`)

Für jede der oben genannten offenen Rollen sind folgende Arbeitsschritte zu erledigen:
- [ ] Variablen in `defaults/main.yml` definieren.
- [ ] Aufgaben in `tasks/main.yml` implementieren.
- [ ] Benötigte Handler/Templates hinzufügen.

## Local AI Build & Test
Die PR-Checkliste in `docs/LOCAL_AI_README.md` enthält mehrere offene Validierungsschritte, die vor einem Merge erfüllt werden müssen:
- [ ] Build-Skript im Dry-Run ausführen.
- [ ] Build-Skript real ausführen.
- [ ] Verfügbarkeit des Modells `llama3:8b` über Ollama sicherstellen.
- [ ] Smoke-Tests (`make lint`, `make test`) erfolgreich durchlaufen.
- [ ] Dokumentation aktualisieren.
- [ ] Merge-Ziel bestätigen (Feature-Branch → main).
