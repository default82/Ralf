# Ralf – Neustart des Automatisierungs-Grundgerüsts

Dieses Repository enthält den neu aufgesetzten Projektstand für **Ralf**, ein automatisiertes Provisioning-System ohne Docker.
Der aktuelle Fokus liegt auf einer klar nachvollziehbaren Ablaufliste inklusive umfassendem Logging und vorbereiteter
Logrotation. Funktionale Module (IPMI, Backups, Multi-Host, Dashboard) werden in späteren Iterationen ergänzt.

## Projektstruktur

```
.
├── config/
│   ├── default.yml          # Konfiguration für Logging und Bootstrapschritte
│   └── logrotate/ralf       # Beispielkonfiguration für logrotate
├── docs/
│   ├── ARCHITECTURE.md      # Architekturüberblick des Grundgerüsts
│   └── SETUP.md             # Erste Schritte & Nutzung des CLI
├── ralf/
│   ├── __init__.py
│   ├── cli.py               # Minimalistische CLI mit plan- und bootstrap-Kommandos
│   ├── config.py            # Datenmodelle für Logging, Pfade und Bootstrapschritte
│   ├── logging.py           # Logging-Initialisierung inkl. Rotationsunterstützung
│   └── workflow.py          # Ausführungshilfen für die Ablaufliste
├── scripts/
│   ├── bootstrap.sh         # Shell-Platzhalter; loggt alle Schritte sichtbar
│   └── install.sh           # Minimaler Installer für Verzeichnisse, Konfig & logrotate
├── LICENSE
├── pyproject.toml           # Projekt- und Abhängigkeitsdefinition
└── README.md
```

Weitere Details zum Setup finden sich im Dokument [`docs/SETUP.md`](docs/SETUP.md) sowie in den
[Legacy-Bootstrap-Notizen](RALF-lxc-bootstrap-v5.1/README.md).

## Nutzung

```bash
pip install -e .
ralf plan
ralf bootstrap --dry-run
ralf bootstrap
```

Für eine Systeminstallation außerhalb der Entwicklungsumgebung steht das Skript
[`scripts/install.sh`](scripts/install.sh) bereit. Es richtet `/etc/ralf`, `/var/log/ralf`, `/var/lib/ralf`
und die logrotate-Konfiguration ein und prüft, ob `python3` verfügbar ist.

Alle Schritte werden auf der Konsole und in der Datei `/var/log/ralf/ralf.log` protokolliert. Über die Konfiguration kann das
Logging für Release-Builds abgeschaltet werden (`logging.release_mode` und `RALF_RELEASE_LOGGING`).

## Logrotation

Das Repository enthält unter `config/logrotate/ralf` eine Vorlage für `/etc/logrotate.d/ralf`. Damit bleiben rotierende Logdateien
verfügbar und die Fehlersuche ist auch nach mehreren Durchläufen möglich.

## Lizenz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE).
