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

## Schnellstart-Installer

Für eine Erstinstallation auf einem frischen System kann das Repository nun direkt über den
Self-Installer (`install.sh`) bezogen werden. Das Skript kümmert sich um den Git-Klon, hält ein
Log unter `/var/log/ralf/installer.log` vor und ruft anschließend den internen Installer des
Repositories auf:

```bash
curl -O https://example.org/ralf/install.sh
chmod +x install.sh
sudo ./install.sh --target-dir /opt/ralf
```

Wird der Self-Installer aus einem bestehenden Git-Checkout gestartet, übernimmt er automatisch die
`origin`-URL sowie den aktuellen Branch als Standardwerte. Beim losgelösten Download (wie im obigen
Beispiel) sollte die Option `--repo-url` auf das gewünschte Repository zeigen. Über die weiteren
Parameter lassen sich Branch und Zielpfad anpassen. Mit `--dry-run` wird nur
angezeigt, welche Schritte ausgeführt würden, ohne Änderungen vorzunehmen. Wenn `whiptail` oder
`dialog` verfügbar ist und das Skript interaktiv gestartet wird, bietet der Self-Installer
automatisch einen Textdialog zur Eingabe der Werte an. Der Dialog kann jederzeit mit `--tui`
erzwungen oder mit `--no-tui` deaktiviert werden; `--quiet` reduziert die Konsolenausgaben auf ein
Minimum, während das Logfile weitergeschrieben wird.

## Nutzung

```bash
pip install -e .
ralf plan
ralf bootstrap --dry-run
ralf bootstrap
```

Für eine Systeminstallation außerhalb der Entwicklungsumgebung steht zusätzlich das Skript
[`scripts/install.sh`](scripts/install.sh) bereit. Es richtet `/etc/ralf`, `/var/log/ralf`,
`/var/lib/ralf` und die logrotate-Konfiguration ein und prüft, ob `python3` verfügbar ist. Der
Self-Installer verwendet dieses Skript automatisch nach dem Klonen.

Alle Schritte werden auf der Konsole und in der Datei `/var/log/ralf/ralf.log` protokolliert. Über die Konfiguration kann das
Logging für Release-Builds abgeschaltet werden (`logging.release_mode` und `RALF_RELEASE_LOGGING`).

## Logrotation

Das Repository enthält unter `config/logrotate/ralf` eine Vorlage für `/etc/logrotate.d/ralf`. Damit bleiben rotierende Logdateien
verfügbar und die Fehlersuche ist auch nach mehreren Durchläufen möglich.

## Lizenz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE).
