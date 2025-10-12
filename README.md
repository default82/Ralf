# Ralf - Automatisierte Systeminstallation

Dieses Projekt ermöglicht die automatisierte Installation und Konfiguration von Systemen basierend auf Hardware-Informationen und Benutzerbestätigungen über Synapse.

## Voraussetzungen

- Hardware mit mindestens 8 GB RAM und 100 GB Festplattenspeicher
- Netzwerkverbindung
- Proxmox VE installiert auf dem Host-System

## Installationsanweisungen

1. **Proxmox VE Installation**:
   - Installieren Sie Proxmox VE auf Ihrem Desktop-Rechner.

2. **Skript ausführen**:
   - Laden Sie das Installationsskript herunter und führen Sie es auf dem Proxmox VE Host aus.

3. **LXC-Container erstellen**:
   - Das Skript erstellt einen LXC-Container für Ralf und die grundlegenden Dienste.

4. **Grundlegende Dienste installieren**:
   - Das Skript installiert die grundlegenden Dienste, darunter PostgreSQL, Ansible, Caddy, Foreman und einen Fileserver.

5. **Fileserver konfigurieren**:
   - Der Fileserver lädt grundlegende Dateien wie Images herunter, jedoch nicht mehr als 25% des verfügbaren Festplattenplatzes.

6. **Netzwerkscan durchführen**:
   - Ralf führt einen Netzwerkscan durch und stellt die erkannten Einstellungen über Synapse zur Bestätigung bereit.

7. **Arbeitsspeicherverteilung vorschlagen**:
   - Ralf macht einen automatischen Vorschlag für die Arbeitsspeicherverteilung basierend auf der verfügbaren Hardware und den installierten Diensten.

## Konfiguration

1. **Netzwerkeinstellungen**:
   - Ralf führt einen Netzwerkscan durch und stellt die erkannten Einstellungen über Synapse zur Bestätigung bereit.
   - Der Benutzer kann die Netzwerkeinstellungen bestätigen oder anpassen.

2. **Arbeitsspeicherverteilung**:
   - Ralf macht einen automatischen Vorschlag für die Arbeitsspeicherverteilung basierend auf der verfügbaren Hardware und den installierten Diensten.
   - Der Benutzer kann diesen Vorschlag bestätigen oder anpassen.

3. **Dienste konfigurieren**:
   - Konfigurieren Sie die einzelnen Dienste wie PostgreSQL, Ansible, Caddy, Foreman und den Fileserver gemäß Ihren Anforderungen.
   - Stellen Sie sicher, dass alle Dienste korrekt konfiguriert sind und miteinander kommunizieren können.

## Verwendung

Nach der Installation können Sie Ralf über das Webinterface oder die Kommandozeile verwenden.

### Webinterface

Das Webinterface von Ralf ist unter `http://localhost:8080` erreichbar. Hier können Sie die verschiedenen Dienste und Betriebssysteme verwalten.

### Kommandozeile

Ralf bietet eine Reihe von Kommandozeilenbefehlen zur Verwaltung der Systeme:

- `ralf install <os_name> --memory 2GB`: Installiert ein Betriebssystem mit dem angegebenen Arbeitsspeicher.
- `ralf configure <service_name> --memory 1GB`: Konfiguriert einen Dienst mit dem angegebenen Arbeitsspeicher.
- `ralf scan network`: Führt einen Netzwerkscan durch.

## Fehlerbehebung

Hier sind einige häufige Probleme und deren Lösungen:

1. **Netzwerkscan funktioniert nicht**:
   - Stellen Sie sicher, dass die Netzwerkverbindung aktiv ist.
   - Überprüfen Sie die Firewall-Einstellungen, um sicherzustellen, dass der Netzwerkscan nicht blockiert wird.

2. **Installation schlägt fehl**:
   - Überprüfen Sie die Hardwareanforderungen und stellen Sie sicher, dass genug Speicher und Festplattenspeicher verfügbar ist.
   - Überprüfen Sie die Konfigurationsdateien auf Fehler.

3. **Dienste starten nicht**:
   - Überprüfen Sie die Logdateien für spezifische Fehlermeldungen.
   - Stellen Sie sicher, dass alle Abhängigkeiten installiert sind.

## Lizenz

Der vollständige Quellcode steht unter der MIT-Lizenz (siehe `LICENSE`).
