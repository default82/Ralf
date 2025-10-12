# Ralf Aufgabenliste

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
