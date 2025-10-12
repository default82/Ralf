# Architekturüberblick – Ralf Grundgerüst

Das Projekt startet bewusst schlank. Ziel ist eine nachvollziehbare Struktur, die alle Aktionen protokolliert und später modular
ausgebaut werden kann.

## Komponenten

- **CLI (`ralf/cli.py`)** – stellt die Befehle `plan` und `bootstrap` bereit.
- **Konfiguration (`ralf/config.py`, `config/default.yml`)** – definiert Logging, Pfade und eine Liste von Bootstrapschritten.
- **Logging (`ralf/logging.py`)** – richtet konsistentes Logging inklusive Rotationsunterstützung ein und respektiert den
  Release-Schalter.
- **Workflow (`ralf/workflow.py`)** – führt die konfigurierten Schritte aus bzw. zeigt sie in einem Trockenlauf an.
- **Logrotate (`config/logrotate/ralf`)** – Beispielvorlage für System-Logrotation.
- **Shell-Bootstrap (`scripts/bootstrap.sh`)** – behält das Prinzip „alle Schritte loggen“ auch für Shell-Abläufe bei.

## Ablauf

1. Die CLI lädt `config/default.yml` (oder eine benutzerdefinierte Datei).
2. Das Logging wird initialisiert. In Entwicklungsumgebungen schreibt es in Konsole und Datei; in Release-Builds kann es
   deaktiviert werden.
3. Der ausgewählte Workflow (`plan` oder `bootstrap`) wird ausgeführt. Jeder Schritt erzeugt Logausgaben.
4. Die Logdateien werden über die Rotationsmechanismen begrenzt, damit alte Durchläufe zur Fehlersuche verfügbar bleiben.

## Erweiterungsideen

- Umsetzung echter Aktionen für die Schritte (z. B. Hardware-Checks, Ansible-Playbooks).
- Aufnahme zusätzlicher Subkommandos für IPMI, Backups und Multi-Host-Szenarien.
- Ergänzung um Tests (Unit-Tests, statische Analysen) sowie CI-Pipelines.
