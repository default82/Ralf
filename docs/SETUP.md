# Erste Schritte mit Ralf

Dieses Dokument beschreibt den aktuellen Entwicklungsstand des Ralf-Grundgerüsts. Die Implementierung konzentriert sich auf eine
strukturierte Ablaufliste mit umfangreichem Logging. Funktionsmodule (IPMI, Backups, Proxmox) folgen in späteren Iterationen.

## Voraussetzungen

- Ubuntu 22.04 LTS oder kompatible Distribution
- Python 3.10 oder neuer
- Schreibrechte für `/var/log/ralf` und `/var/lib/ralf`

## Installation im Entwicklungsmodus

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Systemweite Minimalinstallation

Für eine einfache Grundinstallation außerhalb der Entwicklungsumgebung kann das Skript
[`scripts/install.sh`](../scripts/install.sh) mit Root-Rechten ausgeführt werden:

```bash
sudo ./scripts/install.sh
```

Es legt die benötigten Verzeichnisse an, kopiert die Standardkonfiguration nach `/etc/ralf/config.yml`,
richtet logrotate ein und prüft, ob `python3` verfügbar ist.

## Konfiguration

Die Datei `config/default.yml` definiert die zu protokollierenden Bootstrapschritte. Jeder Schritt besteht aus einem `name`
(Bezeichner) und einer `description` (menschlich lesbar). Weitere Schritte können hinzugefügt oder deaktiviert werden, ohne den
Code zu verändern.

## Ausführung

```bash
ralf plan          # listet alle Schritte auf
ralf bootstrap     # führt den Workflow aus und loggt alle Aktionen
ralf bootstrap --dry-run  # zeigt nur an, welche Schritte laufen würden
```

Die Logs befinden sich standardmäßig unter `/var/log/ralf/ralf.log`. Für Entwickler ist das Logging vollständig aktiviert; in
Release-Builds kann es über `logging.release_mode` oder die Umgebungsvariable `RALF_RELEASE_LOGGING=off` deaktiviert werden.

## Logrotation

Unter `config/logrotate/ralf` befindet sich eine Beispielkonfiguration, die nach `/etc/logrotate.d/ralf` kopiert werden kann.
Sie sorgt dafür, dass bis zu sieben rotierende Dateien aufbewahrt werden – ausreichend für Fehlersuche in frühen Testphasen.

## Nächste Schritte

- Technische Umsetzung der Bootstrapschritte (Pakete installieren, Dienste konfigurieren)
- Integration von IPMI, Backups und Multi-Host-Verwaltung
- Erweiterung um Tests (`mypy`, `pylint`, `shellcheck`)
