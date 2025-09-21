# RALF – Lokale AI-Assistenz auf Proxmox

## Architekturüberblick
- **Proxmox-Host** betreibt einen dedizierten LXC-Container als Heimat für das Entwickler-CoPilot-Stack.
- **[automation/ralf/build_local_ai_lxc.sh](automation/ralf/build_local_ai_lxc.sh)** erzeugt einen reproduzierbaren Debian-Container mit GPU-Forwarding-Optionen, gemeinsamem Modell-Storage (`/srv/ralf/models`) und vorbereiteten Ports für Ollama und Aider.
- **Ollama** stellt lokal das LLM (`llama3:8b`) bereit und exponiert eine HTTP-API, die von Aider genutzt wird.
- **Aider** wird direkt im Container oder via SSH-Tunnel genutzt, um Codeänderungen im Repository umzusetzen.
- **Cloud-Fallback**: Wenn der lokale Container nicht erreichbar ist, können dieselben Aider-Workflows gegen einen externen Ollama- oder OpenAI-kompatiblen Endpunkt laufen; die Konfiguration erfolgt über die jeweiligen `AIDER_`- und `OLLAMA_`-Umgebungsvariablen.

## Setup-Schritte
1. **Vorbereitung**
   - Proxmox-Host aktualisieren und sicherstellen, dass `pct`, `pveam` sowie ein Storage-Target für Container-Templates verfügbar sind.
   - Repository klonen und ggf. Secrets/SSH-Keys bereitstellen.
2. **Container provisionieren**
   - Das Script [`automation/ralf/build_local_ai_lxc.sh`](automation/ralf/build_local_ai_lxc.sh) mit passenden Parametern ausführen (z. B. `./automation/ralf/build_local_ai_lxc.sh --vmid 10060 --hostname lisa-llm`).
   - Optional Parameter per Environment setzen (siehe `--help`).
3. **Ollama vorbereiten**
   - In den Container einloggen (`pct enter 10060`) und den Basismodelldownload starten: `ollama pull llama3:8b`.
   - Sicherstellen, dass ausreichend Speicherplatz auf dem gemounteten Modellverzeichnis vorhanden ist.
4. **Automations-Helfer aktivieren**
   - Aider-Wrapper ausführen (`wrapper/ralf-ai`) oder direkt das Script unter [`automation/ralf/rlwrap/ralf-ai.sh`](automation/ralf/rlwrap/ralf-ai.sh) verwenden.
   - Weitere Automationsziele sind im [Makefile](Makefile) dokumentiert (z. B. `make check` für Linting/Validierung).

## Nutzung
### Lokaler Betrieb (Proxmox LXC + Ollama)
1. Container starten (`pct start 10060`) und Netzwerk prüfen (`pct status 10060`).
2. `ollama serve` sicherstellen (ggf. via `systemctl --user status ollama` oder `ollama ps`).
3. Aider mit lokalem Endpoint verbinden, z. B. `OLLAMA_HOST=http://<container-ip>:11434 aider`. Der Wrapper `wrapper/ralf-ai` setzt empfohlene Defaults (z. B. Modellname, Kontextpfade).
4. Änderungen committen und wie gewohnt testen (`make check`).

### Cloud-Fallback
1. Umgebung auf denselben Code-Stand bringen (z. B. Git-Branch pushen).
2. Remote-Endpunkt konfigurieren (`export OLLAMA_HOST=https://<remote-host>` bzw. entsprechende API-Keys setzen).
3. Aider identisch starten; nur der Endpoint ändert sich. Die Workflows (`wrapper/ralf-ai` oder `aider` direkt) bleiben gleich.
4. Nach Cloud-Nutzung lokalen Container wieder synchronisieren (Pull & ggf. `ollama pull` für neue Modelle).

## Troubleshooting
- **Container startet nicht**: `pct status <vmid>` und `journalctl -u pve-container@<vmid>.service` prüfen; Template ggf. via `pveam download` neu laden.
- **Kein Netzwerk**: Bridge-Konfiguration und DHCP prüfen; `pct exec <vmid> -- ip a` liefert Details.
- **Ollama-Modelle fehlen**: `ollama list` zeigt verfügbare Modelle; fehlende Artefakte erneut mit `ollama pull llama3:8b` laden.
- **Aider-Verbindung scheitert**: Endpoint-URL und offene Ports verifizieren (`ss -tulpn` im Container); bei Cloud-Fallback sicherstellen, dass Firewalls API-Zugriffe erlauben.

## PR-Checkliste
- `make check` ausführen, um YAML- und Ansible-Linting zu validieren (siehe [Makefile](Makefile)).
- Relevante Skripte/Dokumentation aktualisieren (z. B. `automation/ralf/build_local_ai_lxc.sh`, `wrapper/ralf-ai`, diese README).
- Funktionsprüfung dokumentieren (Testprotokoll im PR-Beschreibungstext).
- Merge-Hinweis: Nach Review mit einem regulären Merge-Commit in den Hauptbranch übernehmen (kein Squash/Rebase).
