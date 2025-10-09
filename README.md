# RALF Automation Repository

Dieses Repository enthält das Projekt **RALF-lxc-bootstrap-v5.1**, welches eine Debian-Installation automatisiert in eine
Proxmox-Umgebung überführt und den vollständigen RALF-Stack bereitstellt. Alle Skripte, Konfigurationen und Dokumentationen
finden sich unter `RALF-lxc-bootstrap-v5.1/`.

## Inhalte

- Komplettes Installationsskript (`install.sh`) für die zweiphasige Debian→Proxmox-Bootstrap-Kette.
- Provider- und Service-Skripte für die Erstellung und Konfiguration der LXC-Container.
- Dokumentation des Ablaufs sowie Standardkonfigurationen.

## Verwendung

Folge der Setup-Anleitung in `RALF-lxc-bootstrap-v5.1/README.md`, um die Umgebung aufzusetzen. Stelle sicher, dass alle
notwendigen Abhängigkeiten installiert sind und beachte die Hinweise zur optionalen Omada-Integration.

## Lizenz

Der vollständige Quellcode steht unter der MIT-Lizenz (siehe `LICENSE`).
