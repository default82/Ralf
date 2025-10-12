# Repository Guidance

## Scope
Dieses Dokument gilt für das gesamte Repository.

## Leitprinzipien
- Behandle Ralf als produktionsnahes Projekt mit Fokus auf nachvollziehbares Logging und reproduzierbare Provisionierung.
- Ändere keine Lizenzhinweise; das Projekt bleibt unter der MIT-Lizenz.
- Halte alle README-Dateien aktuell und verweise auf die Setup-Anleitung unter `RALF-lxc-bootstrap-v5.1/README.md`.
- Prüfe neue oder geänderte Skripte darauf, dass sie weiterhin ausführbar sind (`chmod +x`).

## Code-Richtlinien
### Python
- Befolge PEP 8, nutze Typannotationen und dokumentiere öffentliche Funktionen/Methoden via Docstrings.
- Verwende strukturierte Logging-Aufrufe über das zentrale Logging-Modul; direkte `print`-Statements sind zu vermeiden.
- Plane Idempotenz bei Befehlen, die Infrastruktur verändern.

### Shell
- Beginne neue Skripte mit `#!/usr/bin/env bash` und aktiviere `set -euo pipefail`.
- Logge jeden wesentlichen Schritt mit `logger` oder dem projektspezifischen Logging-Wrapper.
- Schreibe Skripte so, dass wiederholte Ausführung keine unerwarteten Nebenwirkungen verursacht.

### YAML & Konfiguration
- Halte Konfigurationsdateien kommentiert und dokumentiere Standardwerte.
- Trenne sensible Daten von Versionskontrolle (Platzhalter, Hinweise auf Secret-Management nutzen).

## Dokumentation
- Ergänze neue Funktionen zeitnah in `docs/SETUP.md` und ggf. `docs/ARCHITECTURE.md`.
- Dokumentiere CLI-Erweiterungen in der README sowie im Hilfetext der CLI.
- Beschreibe Logging- und Troubleshooting-Aspekte, insbesondere wenn neue Logs oder Rotationseinstellungen hinzukommen.

## Tests & Qualitätssicherung
- Führe bei Python-Änderungen mindestens `python -m compileall ralf` aus.
- Nutze vorhandene Linter (`shellcheck`, `ansible-lint`, `pylint`, `mypy`), sofern Änderungen deren Geltungsbereich betreffen.
- Erfasse ausgeführte Tests im Pull-Request-Text sowie in der finalen Zusammenfassung.

## Versions- & Release-Hinweise
- Für frühe Iterationen darf ausführliches Debug-Logging aktiviert bleiben; stelle sicher, dass in produktionsnahen Varianten ein Umschalten möglich ist.
- Ergänze neue Log-Dateien in der Logrotate-Konfiguration, damit die Fehleranalyse langfristig möglich bleibt.

## Kommunikation
- Beschreibe im PR-Text klar, welche Infrastrukturteile betroffen sind (IPMI, Backup, Inventory etc.).
- Verweise bei Breaking Changes auf Migrationspfade oder Übergangsmaßnahmen.
