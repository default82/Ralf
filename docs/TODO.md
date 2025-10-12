# Ralf Aufgabenliste

Diese Aufgabenliste bündelt die offenen Arbeiten für Ralf. Sie ist als lebendes Dokument zu verstehen und muss bei Projektfortschritten aktuell gehalten werden.

## Architektur & Grundlagen
- Ausarbeitung einer Gesamtarchitektur, die Proxmox VE als Hostplattform, das Fileserver-Subsystem und die Synapse-gestützte Interaktion zusammenführt.
- Definition von Sicherheits- und Zugriffskonzepten (SSH, API-Tokens, Netzwerksegmente) für automatisierte Installationsläufe.
- Erstellung eines Betriebs- und Wartungskonzepts inklusive Backup-Strategien für Konfigurations- und Inventardaten.

## Hardware- & System-Erkennung
- Implementierung einer Inventarisierungsroutine, die CPU, RAM, Storage, Netzwerkschnittstellen und Beschleuniger (GPU, TPU) erfasst.
- Ableitung kompatibler Installationsprofile aus der erkannten Hardware (Bare-Metal vs. virtuelle Gäste).
- Validierung der Proxmox-API-Anbindung und Rechte, um Hosts und Ressourcen automatisiert anzulegen.

## Basis-Provisionierung
- Entwicklung eines automatisierten Grundinstallers für Proxmox-Hosts inklusive Paketquellen, Basistools und Sicherheits-Hardening.
- Aufbau wiederholbarer Playbooks/Workflows, um grundlegende Dienste (z. B. Zeitsynchronisation, Monitoring-Agent, Backup-Agent) zu installieren und zu konfigurieren.
- Sicherstellung, dass alle Provisionierungsschritte idempotent ablaufen und Fehler robust behandelt werden.

## Netzwerk & Speicher
- Implementierung eines Netzwerkscans zur Identifikation erreichbarer Subnetze, DHCP-/DNS-Server und freier IP-Bereiche.
- Automatisches Vorschlagen von Netzwerktopologien (Management, Storage, VM-Netz) basierend auf Scan-Ergebnissen.
- Entwicklung einer Speicherverwaltung, die Dateifreigaben und Image-Verzeichnisse so anlegt, dass maximal 25 % der verfügbaren Kapazität belegt werden.

## Arbeitsspeicher- und Ressourcenplanung
- Erstellung eines Empfehlungssystems, das auf Basis der Host-Ressourcen eine sinnvolle RAM- und CPU-Verteilung für VMs/LXC-Container vorschlägt.
- Integration von Regeln für Reserven (z. B. Mindest-RAM für den Hypervisor) und Warnungen bei Überbelegung.
- Darstellung der Vorschläge im Synapse-Dialog inklusive Editier- und Bestätigungsoptionen.

## Bare-Metal-Integration
- Unterstützung für PXE-/ISO-basierte Bare-Metal-Installationen aus dem zentralen Fileserver heraus.
- Verwaltung von Treibern, Firmware und Installations-Skripten für unterschiedliche Hardwareprofile.
- Rückmeldung des Installationsstatus an Ralf, inklusive automatischer Fehleranalyse bei gescheiterten Läufen.

## Synapse-gestützte Interaktion
- Definition eines Dialogflows, der Anwender Schritt für Schritt durch Erkennungs-, Planungs- und Installationsphasen führt.
- Umsetzung bidirektionaler Bestätigungen (z. B. Speicherzuteilung anpassen, Dienste aktivieren/deaktivieren) über Synapse.
- Logging sämtlicher Interaktionen sowie Audit-Trail für Änderungen, die durch Benutzerentscheidungen ausgelöst werden.

## Fileserver & Artefaktverwaltung
- Aufbau eines dedizierten Fileserver-Dienstes zum Herunterladen und Verwalten von Basis-Images, Templates und Konfigurationspaketen.
- Implementierung von Quota- und Bereinigungsläufen, damit der belegte Speicher 25 % der verfügbaren Kapazität nicht überschreitet.
- Versionierung und Integritätsprüfungen (Checksums, Signaturen) für alle gespeicherten Artefakte.

## Monitoring, Logging & Fehlersuche
- Zentralisierung der Installer- und Provisionierungslogs (z. B. via journald oder ELK-Stack) und Definition relevanter Metriken.
- Einrichtung von Alarmierungen für fehlgeschlagene Installationen, überlaufene Speicherquoten und Netzwerkanomalien.
- Dokumentation von Troubleshooting-Leitfäden für häufige Fehlerbilder (API-Zugriff, Hardwareinkompatibilitäten, fehlende Ressourcen).

## Dokumentation & Onboarding
- Erweiterung der Setup- und Betriebsdokumentation um Schritt-für-Schritt-Anleitungen für alle oben genannten Funktionen.
- Erstellung von Architekturdiagrammen und Sequenzabläufen, die den Lebenszyklus eines Installationsprozesses beschreiben.
- Aufbau eines Onboarding-Handbuchs für Operatoren, inklusive Checklisten und Best Practices.

## Tests, Qualität & Release
- Aufbau automatisierter Tests (Unit, Integration, End-to-End) für Hardwareerkennung, Provisionierungs-Workflows und Synapse-Dialoge.
- Integration von CI/CD-Pipelines, die Installations-Simulationen und Linting (Shell, Python) ausführen.
- Definition eines Release-Prozesses mit Versionierung, Changelogs und validierten Artefakten (Pakete, Container-Images).
Diese Liste bündelt die offenen Arbeiten für das Projekt. Sie muss bei Änderungen am Projektstand aktualisiert werden.

## CLI und Workflows
- Implementierung realer Bootstrapschritte anstelle der Platzhalter, inklusive Fehlerbehandlung und Idempotenz.
- Erweiterung der CLI um Subkommandos für IPMI, Backup- und Multi-Host-Szenarien gemäß Architekturfahrplan.
- Einführung eines Plug-in- oder Hook-Systems, damit zusätzliche Schritte modular eingebunden werden können.

## Installer und Provisionierung
- Ergänzung des internen Installers um Validierungen für erforderliche Pakete (z. B. `whiptail`, `logrotate`) und saubere Fehlerausgaben.
- Dokumentierte Option zum Betrieb unter einem dedizierten Servicekonto inkl. angepasster Logrechte.
- Automatisierte Aktualisierung bestehender Installationen (Upgrade-Pfad) sowie ein Deinstallationspfad.

## Logging und Monitoring
- Integration von Systemd-/journald-Logging sowie Export in zentrale Logsysteme.
- Erweiterte Überwachung der Logrotation, inkl. Alarme bei fehlgeschlagenen Rotationen oder vollen Partitionen.
- Konfigurierbare Log-Level pro Modul, um zielgerichtete Fehlerdiagnosen zu ermöglichen.

## Konfiguration und Secrets
- Support für unterschiedliche Umgebungsprofile (Entwicklung, Staging, Produktion) mit überschreibbaren Defaults.
- Einbindung eines Secret-Management-Ansatzes (z. B. HashiCorp Vault oder Ansible Vault) für vertrauliche Parameter.
- Validierung der Konfiguration beim Start mit klaren Fehlermeldungen und Hinweisen zur Behebung.

## Tests und Qualitätssicherung
- Aufbau eines Unit-Test-Sets für CLI, Workflow und Logging-Initialisierung.
- Aktivierung von `mypy`, `pylint` und `shellcheck` im CI, inklusive Fix der aktuell gefundenen Befunde.
- Einrichtung einer kontinuierlichen Integrationspipeline (z. B. GitHub Actions) mit automatischem Artefakt-Upload.

## Dokumentation und Kommunikation
- Erweiterung der Setup-Anleitung um Troubleshooting-Sektionen und häufige Fehlerszenarien.
- Pflege eines Änderungsprotokolls (Changelog) für Releases und interne Iterationen.
- Erstellung von Architekturdiagrammen (z. B. Sequence- und Komponenten-Diagramme) für die Module.

## Packaging und Release
- Vorbereiten eines Release-Prozesses inklusive Versionierung, Tagging und Veröffentlichung auf PyPI.
- Erstellung eines Distributionspakets oder Container-Images für produktionsnahe Deployments.
- Definition von Support- und Wartungsrichtlinien (z. B. LTS-Zyklen, Sicherheitsupdates).
