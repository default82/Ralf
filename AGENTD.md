---
title: R.A.L.F. Agents
description: Übersicht, Funktionen und Kommunikationsstrukturen aller Ralf-Agenten in der Exo-Runtime.
tags: [ralf, exo, agents, automation, homelab]
---

# 🧠 R.A.L.F. Agents

R.A.L.F. (Resourceful Assistant for Labs & Frameworks) nutzt eine modulare Agentenarchitektur innerhalb der **Exo-Runtime**,  
um Infrastruktur, Automatisierung und KI-Funktionen voneinander zu entkoppeln und zugleich dynamisch zu verknüpfen.

---

## Übersicht

| Agent | Hauptaufgabe | Datenquellen | Tools / Schnittstellen | Loops / Flows | Status |
|--------|---------------|---------------|-------------------------|----------------|---------|
| **A_PLAN** | Ressourcenplanung, Platzierung, Simulation | PostgreSQL, Prometheus, Foreman | n8n, Gitea | Main, Adaptive, Discovery | ✅ |
| **A_INFRA** | Deployment, Config, Systemkorrekturen | Vaultwarden, Gitea, Ansible, OpenTofu | n8n | Main, Deploy, Maintenance, Adaptive | ✅ |
| **A_MON** | Überwachung, Health, Logs, Dashboards | Prometheus, Loki | Grafana, Ralf-Core | Main, Adaptive, Learning | ✅ |
| **A_CODE** | Dokumentation, IaC, Updates, Explainability | Gitea, PostgreSQL | n8n | Learning, Maintenance, Policy | ✅ |
| **A_SEC** | Secrets, Compliance, Richtlinienüberwachung | Vaultwarden, Gitea | Matrix, Ralf-Core | Policy, Adaptive | ✅ |
| **FOREMAN** | Hardware-Erkennung, PXE, Rollen-Vorschläge | DHCP, ARP, PXE, Network Scan | Ralf-Core | Discovery, Adaptive | ✅ |

---

## A_PLAN – Resource Planner

**Ziele:**
- Kapazitätsanalyse, Platzierung, Simulation  
- Deployment- und Migrationsempfehlungen  
- Rollenbestimmung für neue Hosts

**Inputs:** Prometheus (Auslastung), PostgreSQL (Inventar), Foreman (Hardware), Vaultwarden (Zugangsdaten)  
**Outputs:** YAML-Pläne → Ralf-Core / n8n  
**Loops:** Main · Adaptive · Discovery

---

## A_INFRA – Infrastructure Agent

**Ziele:**
- Vollautomatische Provisionierung & Konfiguration  
- Self-Healing (Repair-Loop)  
- IaC-Synchronisation mit Gitea

**Inputs:** Vaultwarden, Gitea, PostgreSQL  
**Outputs:** Ansible Playbooks, Tofu-Provisionierung, Logs → Loki  
**Loops:** Deploy · Main · Maintenance · Adaptive

---

## A_MON – Monitoring Agent

**Ziele:**  
- Metriken + Logs korrelieren  
- Auto-Dashboards in Grafana  
- Health + Anomalien an Ralf melden  

**Inputs:** Prometheus, Loki  
**Outputs:** Alerts → Matrix, Status → Ralf  
**Loops:** Main · Learning · Adaptive

---

## A_CODE – Code & Documentation Agent

**Ziele:**  
- IaC-Dokumentation und Explainability  
- Auto-PRs in Gitea mit Begründung  
- Knowledge Consolidation  

**Inputs:** Gitea, PostgreSQL  
**Outputs:** Commits, Markdown-Berichte, Lessons Learned  
**Loops:** Learning · Policy · Maintenance

---

## A_SEC – Security & Policy Agent

**Ziele:**  
- Secret-Rotation, Compliance, Richtlinien  
- Policy-Audit + Notifications  

**Inputs:** Vaultwarden, Gitea  
**Outputs:** Policy-Reports, Security-PRs, Alerts  
**Loops:** Policy · Adaptive

---

## FOREMAN – Discovery Agent

**Ziele:**  
- PXE/DHCP/ARP-Scans  
- Rollenbestimmung  
- Inventar-Erweiterung  

**Outputs:** Vorschläge an Ralf-Core · n8n-Events · Matrix-Hinweise  
**Loops:** Discovery · Adaptive

---

## Kommunikationsdiagramm

```mermaid
flowchart LR
  RALF["Ralf-Core"]
  A_PLAN["Planner"]
  A_INFRA["Infra"]
  A_MON["Monitor"]
  A_CODE["Code"]
  A_SEC["Security"]
  FORE["Foreman"]

  RALF --> A_PLAN & A_INFRA & A_MON & A_CODE & A_SEC
  A_MON --> RALF
  A_PLAN --> RALF
  A_INFRA --> RALF
  A_SEC --> RALF
  FORE --> RALF
