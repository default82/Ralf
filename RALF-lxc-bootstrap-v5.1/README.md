# RALF LXC Bootstrap v5.1

RALF LXC Bootstrap v5.1 richtet eine frisch installierte Debian-Hostmaschine vollständig zu einer produktionsfähigen Proxmox VE (PVE) Umgebung ein und erstellt dort automatisch die benötigten LXC-Container für den RALF-Stack. Das Projekt fokussiert sich auf reproduzierbare Automatisierung ohne Docker (Ausnahme: optionaler vLLM NVIDIA-Stack innerhalb des KI-Containers).

## Überblick

Die Installation erfolgt in zwei Phasen:

1. **Phase 1 – Debian → Proxmox VE**
   * Aktiviert das offizielle Proxmox VE (No-Subscription) Repository.
   * Installiert Proxmox VE inkl. Kernel und Standardpaketen.
   * Setzt den Hostnamen `pve-du-00` und konfiguriert `vmbr0` basierend auf der aktuellen IP-Adresse.
   * Installiert einen systemd-Resume-Service, der nach dem notwendigen Reboot automatisch Phase 2 startet.

2. **Phase 2 – Planung, Provisionierung, Dienste**
   * Startet einen Whiptail-basierten Planer, der alle Netzwerk- und Dienstparameter abfragt und unter `/root/ralf/plan.json` speichert.
   * Erzeugt auf Basis des Plans alle LXC-Container, setzt Tags, weist optional statische IP-Adressen zu und erkennt vorhandene GPUs.
   * Installiert die Kern-Dienste in den Containern (PostgreSQL/Redis, NetBox, Gitea, n8n, Synapse, Vaultwarden, Foreman) und richtet den Caddy Edge-Proxy mit ACME-Unterstützung ein.
   * Erstellt eine Inventardatei (`/root/ralf/inventory.json`) sowie eine Link-Übersicht (`/root/ralf/links.txt`).
   * Optional: Konfiguriert eine TP-Link-Omada-Integration (Best-Effort) und generiert manuelle Nacharbeiten.

## Verzeichnisstruktur

```
RALF-lxc-bootstrap-v5.1/
├─ README.md
├─ install.sh
├─ config/
│  └─ plan.json
├─ providers/
│  └─ pve_provider.sh
└─ scripts/
   ├─ plan_tui.sh
   ├─ install_services.sh
   ├─ setup_edge_caddy.sh
   ├─ omada_integrate.sh
   ├─ pve_install.sh
   ├─ resume.service
   └─ resume.sh
```

## Anforderungen

* Debian 12 (fresh install) oder Proxmox VE 8 Host.
* Root-Rechte und Internetzugang.
* Vorinstallierte Hilfsprogramme: `whiptail`, `jq`, `curl`, `pciutils`, `lshw`, `ca-certificates`, `unzip` (siehe Setup-Anleitung am Ende).

## Datenflüsse

* **Plan** – Der Planer legt sämtliche Entscheidungen in `/root/ralf/plan.json` ab. Dieses JSON dient allen weiteren Skripten als Single Source of Truth.
* **Inventar** – Nach Provisionierung der Container schreibt der Provider das Inventar nach `/root/ralf/inventory.json`.
* **Secrets** – Datenbank-Zugangsdaten landen in `/root/ralf/secrets/db.env`.
* **Links** – Zusammenfassung der wichtigsten URLs in `/root/ralf/links.txt`.

## Kernfunktionen

* Vollautomatische Installation von Proxmox VE (inkl. Persistierung der Netzwerkeinstellungen).
* GPU-Erkennung (NVIDIA, AMD, Intel) und Zuordnung zum KI-Container.
* Flexible IP-Adressierung: DHCP-Standard, optional statische /24-Subnetze pro Kategorie mit Gateway-Konfiguration.
* Auswahl des KI-Stacks (CPU, NVIDIA-Ollama, NVIDIA-vLLM, AMD-ROCm, Intel, Remote).
* Caddy Edge-Proxy mit differenziertem Exposure (public vs. local) und ACME/`tls internal` fallback.
* Foreman/PXE-Modi (disabled, router_relay, foreman_dhcp) mit VLAN-Unterstützung.
* Omada-Integration (Best-Effort) inkl. klarer Anweisungen für NAT und DHCP-Relay.

## Ablauf nach erfolgreicher Installation

1. Die Maschine startet nach Phase 1 automatisch neu.
2. Der Resume-Service startet Phase 2.
3. Der Administrator durchläuft den TUI-Planer.
4. Container werden angelegt, Dienste installiert, Links erzeugt.
5. Optional werden Omada-Schritte ausgegeben.

## Visueller Ablaufplan

```
                                   ┌───────────────────────────┐
                                   │          START            │
                                   └─────────────┬─────────────┘
                                                 │
                           ┌─────────────────────▼─────────────────────┐
                           │ PRECHECKS / INPUTS SAMMELN                │
                           │ - Host: pve01                             │
                           │ - IP-/VLAN-Schema, Subnetze               │
                           │ - CTID/VMID-Bereiche je Kategorie         │
                           │ - Domain extern vorhanden? (FQDN)         │
                           │ - Router PXE-fähig?                       │
                           │ - Omada Controller vorhanden?             │
                           │ - Git-Repo (Inventar/Doku)                │
                           └─────────────┬─────────────┬───────────────┘
                                         │             │
                                         │             │
                           ┌─────────────▼───────┐     │
                           │ NETZWERK/BRIDGES    │     │
                           │ - vmbr/VLAN anlegen │     │
                           │ - Storage-Pools     │     │
                           └─────────────┬───────┘     │
                                         │             │
                     ┌───────────────────▼───────────────────┐
                     │ BASIS-LXC "R.A.L.F." PROVISIONIEREN   │
                     │ - Debian/Ubuntu LXC                   │
                     │ - Ansible/Taskrunner bereitstellen    │
                     │ - SSH / Benutzer / Secrets            │
                     └───────────────────┬───────────────────┘
                                         │
                 ┌───────────────────────▼────────────────────────┐
                 │ CORE-STACK INSTALLIEREN                        │
                 │ - Interner DNS (z.B. unbound/dnsmasq)          │
                 │ - Reverse Proxy (Caddy)                        │
                 │ - PKI/TLS                                      │
                 │ - zentrales Logging/Monitoring-Agent           │
                 └───────────────┬────────────────────────────────┘
                                 │
             ┌───────────────────▼───────────────────────────────────────────┐
             │ DOMAIN EXTERN VORHANDEN?                                     │
             └───────────────┬───────────────────────────────┬──────────────┘
                             │Ja                             │Nein
                             │                                │
        ┌────────────────────▼─────────────┐     ┌────────────▼───────────────────┐
        │ CADDY + LE-ZERTIFIKATE           │     │ INTERNE CA + .home.arpa        │
        │ - DNS-01/HTTP-01                 │     │ - Caddy mit internen Zertifik. │
        │ - öffentl. vHosts vorbereiten    │     │ - nur LAN vHosts               │
        └──────────────────┬───────────────┘     └───────────┬────────────────────┘
                           │                                   │
           ┌───────────────▼──────────────┐         ┌─────────▼─────────┐
           │ ROUTER PXE-FÄHIG?            │         │ OMADA CONTROLLER? │
           └───────────┬──────────────────┘         └─────────┬─────────┘
                       │Ja                                    │Ja
                       │                                       │
        ┌──────────────▼───────────────┐          ┌────────────▼────────────────┐
        │ PXE/NETBOOT EINRICHTEN       │          │ OMADA API/ADOPTION          │
        │ - DHCP/TFTP/NBP              │          │ - Site/Netz-Profile         │
        │ - Images/Bootmenüs           │          │ - VLAN/SSID-Mapping         │
        └──────────────┬───────────────┘          └────────────┬────────────────┘
                       │                                       │
                       └─────────────────────┬─────────────────┘
                                             │
                 ┌───────────────────────────▼───────────────────────────┐
                 │ KATEGORIE-AUSWAHL & CTID/VMID-ZUWEISUNG               │
                 │ (pro gewählter Kategorie Schleife)                    │
                 │ 10 Netzwerkdienste                                     │
                 │ 20 Datenbanken                                         │
                 │ 30 Backup & Sicherheit                                 │
                 │ 40 Web & Admin-Oberflächen                             │
                 │ 50 Verzeichnisdienste & Auth                           │
                 │ 60 Medienserver & Verwaltung                           │
                 │ 70 Doku- & Wissensmanagement                           │
                 │ 80 Monitoring & Logging                                │
                 │ 90 KI & Datenverarbeitung                              │
                 └───────────────┬────────────────────────────────────────┘
                                 │
             ┌───────────────────▼────────────────────────────┐
             │ PRO KATEGORIE: ÖFFENTLICH ODER NUR LOKAL?      │
             └───────────────┬──────────────┬────────────────┘
                             │Öffentlich    │Lokal
                             │              │
      ┌──────────────────────▼───────┐   ┌──▼────────────────────────┐
      │ LXC/VM PROVISIONIEREN       │   │ LXC/VM PROVISIONIEREN      │
      │ - CTID/VMID aus Pool        │   │ - CTID/VMID aus Pool       │
      │ - Paket/Container-Install   │   │ - Paket/Container-Install  │
      │ - Service konfigurieren     │   │ - Service konfigurieren    │
      └───────────────┬─────────────┘   └───────────────┬────────────┘
                      │                                 │
        ┌─────────────▼───────────────┐   ┌─────────────▼───────────────┐
        │ CADDY vHost + TLS + DNS     │   │ INTERNER DNS-Eintrag        │
        │ - Extern erreichbar         │   │ - mTLS/ACL optional         │
        └─────────────┬───────────────┘   └─────────────┬───────────────┘
                      └───────────┬──────────────────────┘
                                  │
                  ┌───────────────▼─────────────────────────┐
                  │ SECURITY & BACKUP EINBINDEN              │
                  │ - FW/ACL, Fail2ban, Updates              │
                  │ - Backup-Job (z.B. restic/Borg/Proxmox)  │
                  │ - Secrets/Passwörter rotieren            │
                  └───────────────┬─────────────────────────┘
                                  │
                  ┌───────────────▼─────────────────────────┐
                  │ MONITORING & LOGGING                    │
                  │ - Agent/Exporter registrieren           │
                  │ - Zentrales Logging (z.B. Loki/Graylog) │
                  │ - Alarme/Benachrichtigungen             │
                  └───────────────┬─────────────────────────┘
                                  │
                ┌─────────────────▼──────────────────────────────┐
                │ VALIDIERUNG / SMOKE TESTS                      │
                │ - DNS, TLS, Ports, Healthchecks                │
                │ - Funktion pro Dienst (HTTP 200, Login, API)   │
                │ - Extern/Intern Routing                        │
                └─────────────────┬──────────────────────────────┘
                                  │
                ┌─────────────────▼──────────────────────────────┐
                │ INVENTAR & DOKU NACH GIT                       │
                │ - hosts.yml / services.yml / networks.yml      │
                │ - README/Runbooks/Changelogs                   │
                │ - Automatisierte Reports (JSON/MD)             │
                └─────────────────┬──────────────────────────────┘
                                  │
                          ┌──────▼──────┐
                          │    ENDE     │
                          └─────────────┘
```

## Aufgaben aus dem Ablaufplan

Die folgende Aufgabenliste überträgt die einzelnen Schritte des Ablaufplans in konkret zu erledigende Arbeitspakete. Sie kann als
Checkliste oder Grundlage für Ticket-Systeme dienen.

### 1. Vorbereitungsphase

- [ ] Ausgangshost identifizieren (z. B. `pve01`) und Hardwaredaten erfassen.
- [ ] Netzwerk- und VLAN-Schema dokumentieren, inklusive Subnetzen und Gateway-Konzept.
- [ ] CTID/VMID-Bereiche pro Kategorie (10er bis 90er Block) festlegen.
- [ ] Verfügbarkeit einer öffentlichen Domain und gewünschter FQDNs prüfen.
- [ ] Prüfen, ob Router PXE-Weiterleitung unterstützt.
- [ ] Status eines TP-Link-Omada-Controllers und API-Zugangsdaten klären.
- [ ] Repositories für Inventar/Dokumentation vorbereiten.

### 2. Infrastruktur-Basis schaffen

- [ ] Notwendige Bridges (`vmbr*`) und VLANs auf dem Proxmox-Host anlegen.
- [ ] Storage-Pools (z. B. ZFS, LVM, Directory) für LXC-Container prüfen oder einrichten.
- [ ] Basis-LXC "R.A.L.F." aufsetzen und Automatisierungs-Tooling (Ansible/Taskrunner) sowie SSH-Zugänge konfigurieren.

### 3. Kern-Stack provisionieren

- [ ] Interne DNS-Lösung (unbound/dnsmasq) vorbereiten.
- [ ] Reverse-Proxy-Struktur mit Caddy planen.
- [ ] PKI/TLS-Strategie definieren (Let's Encrypt vs. interne CA).
- [ ] Logging- und Monitoring-Agenten auswählen und integrieren.

### 4. Domain-abhängige Schritte

- [ ] **Wenn öffentliche Domain verfügbar:** ACME-Validierungsmethode (HTTP-01/DNS-01) wählen und öffentliche vHosts vorbereiten.
- [ ] **Wenn keine öffentliche Domain:** Interne Zertifikatsstelle konfigurieren und `.home.arpa`-Namensschema festlegen.

### 5. Netzwerkservices & Integrationen

- [ ] Router-Fähigkeit für PXE überprüfen und Netboot-Dienste (DHCP/TFTP/NBP) planen.
- [ ] Omada-Controller-Schnittstellen abstimmen, Site-/Netzprofile sowie VLAN-/SSID-Zuordnung vorbereiten.

### 6. Kategorien und Container

- [ ] Für jede ausgewählte Kategorie entscheiden, ob Dienste öffentlich oder nur intern bereitgestellt werden.
- [ ] CTID/VMID je Dienst vergeben und IP-Adressierung (DHCP oder statisch) nach dem Schema `192.168.<Kategorie>.<Host>` planen.
- [ ] Container/VMs provisionieren, Pakete installieren und Dienste konfigurieren.
- [ ] Caddy-vHosts samt TLS-Handling für öffentliche Dienste anlegen.
- [ ] Interne DNS-Einträge bzw. mTLS/ACLs für rein lokale Dienste konfigurieren.

### 7. Betrieb & Absicherung

- [ ] Firewall-Regeln, Fail2ban, Update-Strategien und Secrets-Rotation implementieren.
- [ ] Backup-Jobs (restic/Borg/Proxmox) definieren und testen.
- [ ] Monitoring- und Logging-Anbindung prüfen, Alarme und Benachrichtigungen einrichten.

### 8. Validierung & Dokumentation

- [ ] Smoke-Tests durchführen (DNS, TLS, Portprüfungen, Login-/API-Checks, Routing Innen/Außen).
- [ ] Inventar- und Dokumentationsdateien (`hosts.yml`, `services.yml`, `networks.yml`, Runbooks) aktualisieren.
- [ ] Automatisierte Reports (JSON/Markdown) erzeugen und in Git einchecken.

                           ┌──────▼──────┐
                           │    ENDE     │
                           └─────────────┘
```

## Log-Dateien

* `/root/ralf/logs/install.log` – Hauptlog der Installationsroutine.
* `/root/ralf/logs/provider.log` – Ausgabe der Container-Provisionierung.
* `/root/ralf/logs/services.log` – Ausgabe der Dienst-Installation.

## Fehlersuche

* `journalctl -u ralf-resume.service` – Prüfen des Resume-Services.
* `tail -f /var/log/syslog` – Allgemeine Systemmeldungen.
* `pct status <CTID>` – Status einzelner Container.

## Lizenz

Dieses Projekt steht unter der MIT-Lizenz. Verwende den Code verantwortungsvoll und beachte lokale Sicherheitsrichtlinien.

