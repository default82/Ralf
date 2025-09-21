# RALF – Lokale AI-Assistenz auf Proxmox

Merge PR feature/local-ai-hybrid → main nach erfolgreichem Test

## Architektur & Setup
- **Standardpfad (empfohlen)**: [`automation/ralf/build_local_ai_lxc.sh`](automation/ralf/build_local_ai_lxc.sh) baut und konfiguriert den RALF-LXC auf Proxmox (Standard-VMID `10060`), richtet Mounts, User und Services vollautomatisch ein und bleibt die zentrale Einstiegsmethode.
- **Proxmox-Host** stellt die Virtualisierungsumgebung bereit und bindet `/srv/ralf` in den Container ein, damit Repositories und Modelle persistent bleiben.
- **Ollama** läuft im Container als Systemdienst und bedient das Modell `llama3:8b` über `http://127.0.0.1:11434`.
- **Aider** (bzw. der Wrapper [`wrapper/ralf-ai`](wrapper/ralf-ai)) greift auf die lokale Ollama-Instanz zu und automatisiert Codeänderungen im gemounteten Repository.
- **Cloud-Fallback** nutzt dieselben Werkzeuge; bei Bedarf werden lediglich Endpoint (`OPENAI_API_BASE`) und Schlüssel (`OPENAI_API_KEY`) auf einen externen Dienst gesetzt.

### Setup auf Proxmox
1. **Dry-Run des Container-Builds**
   ```bash
   automation/ralf/build_local_ai_lxc.sh --dry-run
   ```
   Prüft Konnektivität, benötigte Pakete und reserviert die VMID, ohne Änderungen vorzunehmen.
2. **Real-Run durchführen**
   ```bash
   sudo automation/ralf/build_local_ai_lxc.sh
   ```
   Erstellt den LXC, legt `/srv/ralf` an und trägt den Bind-Mount automatisch in `/etc/pve/lxc/10060.conf` ein.
3. **Modell bereitstellen**
   ```bash
   pct enter 10060
   ollama pull llama3:8b
   ```
   Anschließend optional `systemctl --user status ollama` oder `ollama ps`, um den Dienst zu überprüfen.
4. **Wrapper & Tests nutzen**
   ```bash
   pct exec 10060 -- ralf-ai "<task-beschreibung>"
   pct exec 10060 -- make lint
   pct exec 10060 -- make test
   ```
   Der Wrapper setzt die notwendigen Variablen; Tests müssen vor jedem Merge grün sein.
   `make lint` ruft [`tests/shellcheck.sh`](tests/shellcheck.sh) auf, das `shellcheck` für alle Shell-Skripte (inklusive Unterordnern wie `automation/ralf/rlwrap/`) startet. Stelle sicher, dass `shellcheck` verfügbar ist oder installiere es per Paketmanager.

### Legacy- und Migrationspfade
Historische Workflows (Docker Compose, Terraform Cloud-Stacks, manuelle LXC-Anlage) gelten als **Legacy** und werden nur noch im [Hybrid-Guide](docs/LOCAL_AI_README.md) dokumentiert. Neue Installationen folgen ausschließlich dem Proxmox-Skript oben.

## Nutzung
### Lokaler Betrieb (Proxmox LXC + Ollama)
1. Container starten und prüfen:
   ```bash
   pct start 10060
   pct status 10060
   ```
2. Aider-Wrapper direkt im Container anstoßen oder remote ausführen, z. B.:
   ```bash
   pct exec 10060 -- ralf-ai "Implementiere neues Feature"
   ```
   Der Wrapper setzt alle erforderlichen `OLLAMA_`- und `AIDER_`-Variablen.
3. Tests nach Änderungen durchführen:
   ```bash
   pct exec 10060 -- make lint
   pct exec 10060 -- make test
   ```
4. Ergebnisse committen und wie gewohnt in das zentrale Git-Repository pushen.
`make lint` nutzt [`tests/shellcheck.sh`](tests/shellcheck.sh), um `shellcheck` auf sämtlichen Shell-Skripten im Repository auszuführen.

### Cloud-Fallback
1. Endpoint und Schlüssel exportieren:
   ```bash
   export OPENAI_API_BASE="https://<cloud-endpunkt>"
   export OPENAI_API_KEY="<token>"
   ```
2. Wrapper bzw. `aider` wie gewohnt starten (lokal oder im Container).
3. Nach Cloud-Nutzung wieder auf lokale Werte zurücksetzen oder Variablen unsetten.

## Troubleshooting
- **Netzwerk im Container fehlt**: `pct exec 10060 -- ip a` prüfen, Bridge-Konfiguration (`vmbr`) und DHCP am Proxmox-Host kontrollieren.
- **Ollama-Service läuft nicht**: `pct exec 10060 -- systemctl --user status ollama` auswerten; bei Fehlern Logs via `journalctl --user -u ollama` einsehen und Dienst mit `systemctl --user restart ollama` neu starten.
- **Wrapper nicht auffindbar**: Sicherstellen, dass `/srv/ralf/wrapper/ralf-ai` ausführbar ist (`chmod +x`) und der Bind-Mount aktiv ist (`pct exec 10060 -- mount | grep /srv/ralf`).
- **API-Aufrufe schlagen fehl**: Endpoints (`OLLAMA_HOST`, `OPENAI_API_BASE`) und Firewalls/Reverse-Proxies kontrollieren; bei Cloud-Fallback zusätzlich TLS-Zertifikate prüfen.

## PR-Checkliste
- `pct exec 10060 -- make lint` und `pct exec 10060 -- make test` ausführen; Ergebnisse im PR dokumentieren.
- Relevante Skripte und Dokumentation aktualisieren (`automation/ralf/build_local_ai_lxc.sh`, `wrapper/ralf-ai`, diese README bei Prozessänderungen).
- Sicherstellen, dass Ollama (`ollama ps`) und der Wrapper (`ralf-ai --help`) nach Änderungen weiterhin funktionieren.
- Netzwerk- und Mount-Konfiguration verifizieren, falls die Änderung Auswirkungen auf `/srv/ralf` oder Container-Start hat.
- Nach Review per Merge-Commit in `main` integrieren (kein Squash/Rebase).
