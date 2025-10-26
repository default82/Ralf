# Ralf

R.A.L.F. – Resourceful Assistant for Labs and Frameworks

KI-gesteuertes, selbstadaptives Homelab-Ökosystem

Kurzfassung: R.A.L.F. ist die zentrale KI deines Homelabs. Er orchestriert Dienste, überwacht Infrastruktur, heilt sich selbst, lernt aus Ereignissen und optimiert Ressourcen – alles lokal auf Proxmox, mit klaren APIs und nachvollziehbaren Änderungen (Explainability & Audit).

Inhaltsverzeichnis

1. Ziele & Prinzipien

2. Architekturüberblick

3. Komponenten

4. Datenflüsse & Hauptabläufe

4.1 Deployment Flow (Beispiel Jellyfin)

4.2 Main-Loop (Health, Self-Healing, Learning)

4.3 Maintenance & Repair

4.4 Learning & Explainability

4.5 Policy & Security

4.6 Telemetry & External Insights

4.7 Network Discovery Loop

4.8 Adaptive Infrastructure Loop

5. Datenhaltung & Schnittstellen

6. Sicherheit & Compliance

7. Betrieb, Monitoring & Backups

8. Roadmap & Checkpoints

9. Mermaid-Gesamtarchitektur

10. Glossar

1. Ziele & Prinzipien

Autonomie: Dienste installieren, konfigurieren, überwachen und reparieren sich weitgehend selbst.

Lernen: Mustererkennung aus Logs/Metriken; Konsolidation in einem Wissensspeicher.

Transparenz: Jede Entscheidung ist erklärbar (Explainability) und auditierbar (Gitea/Commits).

APIs statt „Querschießen“: Zugriff auf Systeme nur über dokumentierte Schnittstellen.

Lokal first: Betrieb lokal auf Proxmox, offline-fähig; externe Ressourcen optional.

Sicherheit: Strikte Secret-Governance über Vaultwarden; regelmäßige Rotation & Policy-Checks.

2. Architekturüberblick

R.A.L.F. läuft innerhalb Exo (KI-Runtime). Die persistenten Kerndienste (PostgreSQL, Gitea, Vaultwarden, Vector-DB) sowie Orchestrierung/Monitoring (n8n, Ansible, OpenTofu, Prometheus, Loki, Grafana) laufen als VMs/LXCs auf Proxmox.
Foreman ist Teil der R.A.L.F.-Domäne (Discovery/Inventar), aber reagiert auch auf externe Events (neuer Host).

3. Komponenten
Kategorie	Dienst/Agent	Aufgabe (Kurz)
KI-Core	Ralf-Core	Reasoner/Planner/Coordinator, Chat/UI-Interface
Agenten	A_PLAN	Ressourcenplanung, Platzierung, Simulation
	A_INFRA	Provisionierung & Konfiguration (OpenTofu/Ansible)
	A_MON	Health, Auto-Dashboards, Anomalien (Prom/Loki)
	A_CODE	IaC, Doku, PRs/Commits (Gitea)
	A_SEC	Secrets, Policy & Compliance
Runtime	Exo	Hostet Ralf-Core & Agenten
Discovery	Foreman	PXE/DHCP/Inventar, Rollen-Vorschläge
Orchestrierung	n8n	Workflows, Approvals, Notifications
Automation	Ansible / OpenTofu	Konfig & IaC-Provisionierung
Monitoring	Prometheus / Loki / Grafana	Metriken, Logs, Dashboards
Datenhaltung	PostgreSQL	Inventar, Status, Historie, Audit
	Gitea	Repos, IaC, Playbooks, Doku
	Vaultwarden	Secrets, Tokens, Credentials
	Vector-DB	Wissensspeicher/Langzeitmuster
Interfaces	Synapse (Matrix)	Chat-Befehle, Rückmeldungen
	Web-UI	Geplantes grafisches Frontend
4. Datenflüsse & Hauptabläufe
4.1 Deployment Flow (Beispiel Jellyfin)

Input: Matrix-Befehl „Installiere Jellyfin“.

Intent & Planung: Ralf erkennt Auftrag; A_PLAN prüft Ressourcen (PG) & Templates (Gitea).

Workflow: Ralf erzeugt n8n-Task „Deploy Jellyfin“.

Provisionierung: A_INFRA → OpenTofu (LXC/VM) → Ansible (Install/Config); Secrets via Vaultwarden.

Monitoring & Feedback: Exporter, Metriken/Logs aktiv; A_MON bewertet; Ralf antwortet im Chat.

Persistenz: Status, IaC, Dashboards, Audit-Trail werden aktualisiert.

4.2 Main-Loop (Health, Self-Healing, Learning)

Sammeln (Prom/Loki) → Bewerten (Ralf) → Korrigieren (A_INFRA via Ansible/Tofu) → Dokumentieren (A_CODE/Gitea) → Lernen (Vector-DB).

Ergebnis: Stabilität, Selbstheilung, kontinuierliche Optimierung.

4.3 Maintenance & Repair

Backups (bei PBS-Erkennung automatisch geplant).

Repair-Loop (Redeploy/Restart bei Failure).

Resource Balancing (mehrere Nodes, Simulation & Re-Placement).

4.4 Learning & Explainability

Knowledge Consolidation (Erfahrungsobjekte zu Incidents/Deploys).

Pattern Recognition (wiederkehrende Fehler, Vorhersagen).

Explainability & Audit Trail (Auto-PRs/Commits mit Begründungen in Gitea).

4.5 Policy & Security

Compliance-Checks, Secret-Rotation, Richtlinien-Monitoring, Notifications.

Strikte Nutzung dokumentierter APIs; keine Direktzugriffe „quer“.

4.6 Telemetry & External Insights

Aggregation von Trends (Prometheus) → Reports/Dashboards (Grafana).

Optionaler Telemetry-Export, ohne sensible Daten.

4.7 Network Discovery Loop

Zyklische Scans über Foreman (DHCP/ARP/PXE).

Ralf/A_PLAN klassifizieren Änderungen, n8n aktualisiert Inventar (PG).

Benachrichtigungen/Approvals via Matrix; Secrets für Scans via Vaultwarden.

4.8 Adaptive Infrastructure Loop

Analyse → Planung (Simulation) → Validierung (Policies/Secrets) → Ausführung (Tofu/Ansible) → Dokumentation (Gitea) → Lernen (Vector-DB) → Feedback (Matrix/UI).

Reagiert auf neue Hardware, Lastdrift, PBS, Kapazitätsengpässe.

5. Datenhaltung & Schnittstellen

PostgreSQL: Inventar, Laufzeitstatus, Historie, Audit, Decisions.

Gitea: „Single Source of Truth“ für IaC/Playbooks/Doku (PR-basiert).

Vaultwarden: zentrale Secret-Quelle (scoped Tokens für Tools).

Vector-DB: Muster, Heuristiken, Lessons Learned.

APIs: n8n REST, Ansible/Semaphore, OpenTofu Provider, Prom/Loki Queries, Foreman API, Matrix Webhooks.

6. Sicherheit & Compliance

Least Privilege & Scopes (Vaultwarden → Tool-spezifische Zugänge).

Rotation-Policies (zeitgesteuert & anlassbezogen).

Compliance-Loop (A_SEC prüft TLS, Ports, Versionen, Richtlinien-Abweichungen).

Audits (Gitea Commits/PRs mit Auto-Labels & Change-Reasons).

7. Betrieb, Monitoring & Backups

Monitoring: Prometheus (Pull), Loki (Logs), Grafana (Dashboards, Alerts).

Backups: PBS-Erkennung triggert Sicherungsaufgaben; Restore-Prozeduren dokumentiert.

Notifications: Matrix (Fehler, Deploys, Fragen/Approvals).

Self-Checks: Ralf überwacht eigene Dienste (Watchdogs/Health).

8. Roadmap & Checkpoints

Phase 1 – Baseline

 PVE Node + VLAN/DNS/Storage steht

 PostgreSQL, Gitea, Vaultwarden betriebsbereit

 Prometheus, Loki, Grafana mit Basis-Dashboards

Phase 2 – Orchestrierung & Discovery

 n8n Flows (Health-Loop, Deploy, Repair)

 Foreman Discovery + Event → n8n/Ralf

Phase 3 – KI-Schicht

 Exo + Ralf-Core (lokales LLM, z. B. Mistral/Llama via Ollama/vLLM)

 Agenten: A_PLAN, A_INFRA, A_MON, A_CODE, A_SEC

Phase 4 – Autonomie

 Adaptive Infrastructure Loop aktiv (Simulation → Placement)

 Policy/Secret-Rotation automatisiert

 Explainability & Audit-Auto-PRs

Phase 5 – Feinschliff

 Web-UI (Status, Fleet, Actions, Explainability)

 Telemetry-Exports, Reports

9. Mermaid-Gesamtarchitektur

Hinweis: Dark-Theme & ELK-Layout aktiviert; getestet in Obsidian & mermaid.live.

---
config:
  theme: dark
  layout: elk
  elk:
    algorithm: layered
---

flowchart TD

classDef interface fill:#e4d8f9,stroke:#7a42c5,stroke-width:2px;
classDef brain fill:#cbffe6,stroke:#239955,stroke-width:2px;
classDef agent fill:#fff5cc,stroke:#d6b013,stroke-width:2px;
classDef orchestrator fill:#d4edfa,stroke:#1581aa,stroke-width:2px;
classDef core fill:#ffe6dc,stroke:#a65400,stroke-width:2px;
classDef monitor fill:#f5f5f5,stroke:#777,stroke-width:1px;
classDef external fill:#f8f8f8,stroke:#aaa,stroke-dasharray:3 3;
classDef active stroke:#e60000,stroke-width:3px;
classDef loop stroke:#00994d,stroke-width:3px;
classDef maintenance stroke:#0073e6,stroke-width:3px;
classDef learning stroke:#8000ff,stroke-width:3px;
classDef policy stroke:#e6a000,stroke-width:3px;
classDef discovery stroke:#00aaff,stroke-width:3px;
classDef adaptive stroke:#00d1a0,stroke-width:3px;

subgraph PVE["Proxmox-Node-01 – Hostsystem"]
direction TB

  subgraph CORE["Core-Dienste (persistent)"]
    PG["PostgreSQL – Inventar / Status / Verlauf"]:::core
    GIT["Gitea – Code / IaC / Playbooks / Versionierung"]:::core
    VAULT["Vaultwarden – Secrets / Tokens / Credentials"]:::core
    KB["Vector-DB – Wissensspeicher / Langzeitgedächtnis"]:::core
  end

  subgraph ORCH["Orchestrierung & Monitoring"]
    N8N["n8n – Workflow-Orchestrierung"]:::orchestrator
    ANS["Ansible – Konfiguration / Automatisierung"]:::core
    TOFU["OpenTofu – Infrastruktur-Provisionierung"]:::core
    PROM["Prometheus – Metrik-Sammlung"]:::monitor
    LOKI["Loki – Log-Sammlung"]:::monitor
    GRAF["Grafana – Dashboards"]:::monitor
  end

  subgraph EXO["Exo – KI-Runtime (Ralf & Agenten)"]
  direction TB
    RALF["Ralf-Core – KI-Zentrale / Reasoner / Planner"]:::brain
    FORE["Foreman – Discovery / PXE / Rollen-Erkennung"]:::brain
    A_PLAN["Agent Planner – Ressourcenplanung / Placement"]:::agent
    A_INFRA["Agent Infra – Deployment & Config (Ansible / Tofu)"]:::agent
    A_MON["Agent Monitor – Health & Logs (Prom / Loki)"]:::agent
    A_CODE["Agent Code – IaC, Doku & Updates"]:::agent
    A_SEC["Agent Security – Secrets, Policy & Compliance"]:::agent
  end

  subgraph UI_BLOCK["Benutzerschnittstellen"]
    UI["Web-UI (geplant)"]:::interface
    SYN["Synapse / Matrix-Chat"]:::interface
  end
end

NEWNODE["Neuer entdeckter Host im Netzwerk"]:::external
PBS["Proxmox Backup Server erkannt"]:::external

SYN -->|"Chat-Aufträge / Statusanfragen"| RALF
UI -->|"Manuelle Steuerung / Visualisierung"| RALF
RALF -->|"Zuweisung von Aufgaben / Planung"| A_PLAN
RALF -->|"Deployment-Aufträge"| A_INFRA
RALF -->|"Monitoring-Aufgaben"| A_MON
RALF -->|"Code-Änderungen / Doku"| A_CODE
RALF -->|"Security-Checks / Policies"| A_SEC
RALF -->|"Startet Workflows / n8n"| N8N

A_INFRA -->|"Playbooks ausführen"| ANS
A_INFRA -->|"Provisionierung durchführen"| TOFU
A_MON -->|"Metriken abfragen"| PROM
A_MON -->|"Logs analysieren"| LOKI
A_MON -->|"Dashboards pflegen"| GRAF
A_CODE -->|"Änderungen / IaC-Sync"| GIT
A_SEC -->|"Secrets abrufen"| VAULT

N8N -->|"Startet Ansible-Jobs"| ANS
N8N -->|"Ruft OpenTofu-Module auf"| TOFU
N8N -->|"Speichert Workflow-Ergebnisse"| PG
N8N -->|"Schreibt Code"| GIT
N8N -->|"Verwendet Secrets"| VAULT
N8N -->|"Liest Metriken / Logs"| PROM
N8N -->|"Sendet Notifications"| SYN

PROM -->|"Metriken / Statusdaten"| RALF
LOKI -->|"Fehler / Logs"| RALF
RALF -->|"Aktualisiert IaC / Code"| GIT
RALF -->|"Schreibt Status / Lernfortschritt"| PG
RALF -->|"Speichert Wissen / Muster"| KB

FORE -->|"Systemerkennung / Vorschläge"| RALF
NEWNODE -->|"Signalisiert neuen Host"| FORE
PBS -->|"Signalisiert Backup-Möglichkeit"| RALF
VAULT -->|"Gibt Secrets an Tools"| ANS
VAULT -->|"Gibt Secrets an Tools"| TOFU
VAULT -->|"Gibt Tokens an Tools"| N8N

SYN -->|"Anfrage: 'Installiere Jellyfin'"| RALF:::active
RALF -->|"Intent erkannt / Planungsphase"| A_PLAN:::active
A_PLAN -->|"Ressourcen prüfen"| PG:::active
A_PLAN -->|"Template finden"| GIT:::active
A_PLAN -->|"Plan an Ralf"| RALF:::active
RALF -->|"Startet Workflow"| N8N:::active
N8N -->|"Task 'Deploy Jellyfin'"| A_INFRA:::active
A_INFRA -->|"Holt Secrets"| VAULT:::active
A_INFRA -->|"Erstellt Umgebung"| TOFU:::active
A_INFRA -->|"Installiert Jellyfin"| ANS:::active
ANS -->|"Meldet Logs / Status"| LOKI:::active
PROM -->|"Health-Daten"| A_MON:::active
A_MON -->|"Bewertet Erfolg"| RALF:::active
RALF -->|"Ergebnis 'Jellyfin installiert'"| SYN:::active

RALF -->|"Health-Checks / Statusabfragen"| A_MON:::loop
A_MON -->|"Sammelt Metriken"| PROM:::loop
A_MON -->|"Analysiert Logs"| LOKI:::loop
PROM -->|"Überträgt Daten"| RALF:::loop
LOKI -->|"Überträgt Ereignisse"| RALF:::loop
RALF -->|"Erkennt Anomalien"| A_INFRA:::loop
A_INFRA -->|"Korrigiert Systeme / Neustarts"| ANS:::loop
A_INFRA -->|"Aktualisiert IaC"| GIT:::loop
RALF -->|"Schreibt Lernergebnisse"| KB:::loop
RALF -->|"Aktualisiert Status"| PG:::loop
A_MON -->|"Erstellt Auto-Dashboards"| GRAF:::loop

PBS -->|"Löst Sicherungs-Deploy aus"| RALF:::maintenance
RALF -->|"Plant Backup"| N8N:::maintenance
N8N -->|"Startet Backup-Workflow"| ANS:::maintenance
ANS -->|"Sichert Daten / Validiert"| PG:::maintenance
A_INFRA -->|"Repair-Loop bei Fehlern"| ANS:::maintenance
A_INFRA -->|"Re-Deploy fehlerhafter Dienste"| TOFU:::maintenance
A_PLAN -->|"Resource Balancing (mehrere Nodes)"| TOFU:::maintenance
A_PLAN -->|"Aktualisiert Placement"| PG:::maintenance

RALF -->|"Knowledge Consolidation"| KB:::learning
RALF -->|"Pattern Recognition in Logs"| LOKI:::learning
A_CODE -->|"Generiert Fix-Playbooks"| GIT:::learning
RALF -->|"Aktualisiert Agentenwissen"| EXO:::learning
RALF -->|"Erstellt Audit Trails"| PG:::learning
A_CODE -->|"Erklärt Änderungen (Explainability)"| GIT:::learning

A_SEC -->|"Policy Compliance Check"| RALF:::policy
RALF -->|"Revalidiert Secrets"| VAULT:::policy
A_SEC -->|"Secret Rotation"| VAULT:::policy
A_SEC -->|"Überwacht Richtlinienänderungen"| GIT:::policy
A_SEC -->|"Sendet Policy-Notifications"| SYN:::policy

PROM -->|"Aggregierte Daten / Trends"| RALF:::learning
RALF -->|"Exportiert Insights"| GRAF:::learning
GRAF -->|"Generiert Telemetry Export"| PG:::learning

subgraph NETWORK["Erkenne das Netzwerk – Discovery Loop"]
direction LR
    RALF -->|"Startet regelmäßigen Scan"| FORE:::discovery
    FORE -->|"DHCP / ARP / PXE-Scan-Ergebnisse"| RALF:::discovery
    RALF -->|"Erkennt neue / geänderte Hosts"| A_PLAN:::discovery
    A_PLAN -->|"Rollen-Vorschläge / Änderungen"| N8N:::discovery
    N8N -->|"Aktualisiert Inventar"| PG:::discovery
    VAULT -->|"Gibt Zugangsdaten für Scans"| FORE:::discovery
    N8N -->|"Sendet Hinweis an Admin"| SYN:::discovery
end

subgraph ADAPT["Adaptive Infrastructure Loop"]
direction LR
FORE -->|"Neue Hosts / Hardware / PBS"| RALF:::adaptive
A_MON -->|"Ressourcendaten / Metriken"| RALF:::adaptive
RALF -->|"Analyse / Optimierungsempfehlung"| A_PLAN:::adaptive
A_PLAN -->|"Simuliert & plant Umverteilung"| RALF:::adaptive
A_PLAN -->|"Plant Migration / Scaling"| A_INFRA:::adaptive
A_PLAN -->|"Plant Dokumentation"| A_CODE:::adaptive
A_SEC -->|"Policy-Check / Secret-Validation"| RALF:::adaptive
A_INFRA -->|"Deployment / Migration"| TOFU:::adaptive
A_INFRA -->|"Re-Konfiguration"| ANS:::adaptive
A_INFRA -->|"Speichert Änderungen"| PG:::adaptive
A_CODE -->|"Aktualisiert IaC / Doku"| GIT:::adaptive
RALF -->|"Lernt aus Ergebnissen"| KB:::adaptive
RALF -->|"Sendet Benachrichtigungen"| SYN:::adaptive
end

10. Glossar

IaC: Infrastructure as Code (Tofu/Ansible/Git).

Exporter: Prometheus-Komponenten, die Metriken bereitstellen.

Explainability: Nachvollziehbare Begründung, warum eine Entscheidung getroffen wurde.

Self-Healing: Automatische Korrektur bei Fehlern (Repair-Loop).

Adaptive Loop: Autonomes Re-Balancing, Migration, Scaling anhand von Daten & Policies.
