# Erste Schritte mit Ralf

Dieses Dokument beschreibt den aktuellen Entwicklungsstand des Ralf-Grundgerüsts. Die Implementierung konzentriert sich auf eine
strukturierte Ablaufliste mit umfangreichem Logging. Funktionsmodule (IPMI, Backups, Proxmox) folgen in späteren Iterationen.

## Voraussetzungen

- Ubuntu 22.04 LTS oder kompatible Distribution
- Python 3.10 oder neuer
- Schreibrechte für `/var/log/ralf` und `/var/lib/ralf`
- Möglichkeit, Systembenutzer und -gruppen anzulegen (für zukünftige Dienste; aktuelle Installer-Schritte verbleiben unter Root)

## Installation im Entwicklungsmodus

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Systemweite Minimalinstallation

Für eine einfache Grundinstallation außerhalb der Entwicklungsumgebung stehen zwei Schritte zur Verfügung:

1. **Self-Installer (`install.sh`)** – lädt das Repository herunter oder aktualisiert es und ruft anschließend den internen
   Installer auf. Beispielaufruf:

   ```bash
   curl -O https://example.org/ralf/install.sh
   chmod +x install.sh
   sudo ./install.sh --target-dir /opt/ralf
   ```

   Startet der Self-Installer aus einem bestehenden Checkout, übernimmt er automatisch die `origin`-URL und den aktuellen
   Branch als Standard. Liegen keine lokalen Vorgaben vor, setzt er auf das offizielle Repository `git@github.com:default82/Ralf.git`.
   Erkennt er dabei eine GitHub-HTTPS-URL, wechselt er automatisch zur SSH-Variante, sodass vorhandene SSH-Keys ohne Benutzer-/Passworteingabe genutzt werden.
   Beim separaten Download empfiehlt es sich, `--repo-url` explizit auf das gewünschte Repository zu
   setzen. Mit `--dry-run` kann überprüft werden, welche Aktionen ausgeführt würden, ohne Änderungen vorzunehmen. Standardmäßig werden
   alle Schritte nach `/var/log/ralf/installer.log` protokolliert. Wenn `whiptail` oder `dialog` installiert ist und das Skript
   interaktiv läuft, öffnet sich automatisch eine einfache TUI, über die sich Repository-URL, Branch, Zielpfad und Dry-Run
   anpassen lassen. Mit `--tui` kann der Dialog auch in nicht-interaktiven Standardsessions erzwungen und mit `--no-tui`
   vollständig unterdrückt werden. Die Option `--quiet` reduziert die Konsolenausgabe, lässt das Logfile jedoch weiterlaufen.

2. **Interner Installer (`scripts/install.sh`)** – richtet `/etc/ralf`, `/var/log/ralf`, `/var/lib/ralf` sowie logrotate ein und
   prüft, ob `python3` verfügbar ist. Er kann direkt aus dem Repository ausgeführt werden:

   ```bash
   sudo ./scripts/install.sh
   ```

Der Self-Installer verwendet das interne Skript automatisch, sodass keine manuellen Schritte notwendig sind, sobald das
Repository unter dem Zielpfad bereitsteht.

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

## Servicekonto und Log-Berechtigungen

Das Installationsskript legt einen dedizierten Systembenutzer sowie eine Systemgruppe `ralf` an und überträgt den Besitz von
`/var/log/ralf` an dieses Konto. Damit kann `logrotate` neue Dateien mit `ralf:ralf` als Besitzer erzeugen und Dienste, die
unter diesem Konto laufen, behalten Schreibzugriff auf ihre Logdateien. Wer lieber eigene Accounts nutzt, kann die erzeugten
Benutzer- und Gruppennamen nach der Installation anpassen – die Logrotate-Konfiguration erwartet lediglich, dass der Besitzer
von `/var/log/ralf` mit den dort hinterlegten Angaben übereinstimmt.

## Nächste Schritte

- Technische Umsetzung der Bootstrapschritte (Pakete installieren, Dienste konfigurieren)
- Integration von IPMI, Backups und Multi-Host-Verwaltung
- Erweiterung um Tests (`mypy`, `pylint`, `shellcheck`)
