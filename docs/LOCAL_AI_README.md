# Local AI Hybrid Guide

Dieser Guide beschreibt den Hybrid-Container **lisa-llm** für das Homelab "R.A.L.F.". 
Er kombiniert einen lokalen Ollama-Dienst im Proxmox-LXC mit einem optionalen Cloud-Fallback, 
wobei alle Automatisierungen innerhalb dieses Repositories definiert sind.

## Architekturüberblick
- **Proxmox-LXC**: Container `lisa-llm` (Standard-VMID `10060`) läuft auf `pve01` und bindet `/srv/ralf` vom Host als persistentes Volume ein.
- **Ollama**: Liefert lokal das Modell `llama3:8b` über `http://localhost:11434/v1`.
- **Aider + Wrapper**: [`automation/ralf/rlwrap/ralf-ai.sh`](../automation/ralf/rlwrap/ralf-ai.sh) startet Aider mit sicheren Defaults, Git-Hygiene und 
  Branch-Prüfung.
- **Cloud-Fallback**: Über Umgebungsvariablen `OPENAI_API_BASE`/`OPENAI_API_KEY` kann auf jeden OpenAI-kompatiblen Dienst gewechselt werden.

## Setup-Schritte
1. **Dry-Run durchführen**
   ```bash
   bash automation/ralf/build_local_ai_lxc.sh --dry-run
   ```
   Dadurch erhältst du eine Übersicht aller geplanten `pct`-Befehle ohne Änderungen.

2. **Container provisionieren**
   ```bash
   sudo bash automation/ralf/build_local_ai_lxc.sh
   ```
   Das Skript stellt das Ubuntu-Template bereit, erstellt/aktualisiert den Container, richtet Mounts und Features ein, 
   installiert Ollama und Aider und kopiert den Wrapper nach `/usr/local/bin/ralf-ai`.

3. **Modell synchronisieren**
   ```bash
   pct exec 10060 -- ollama pull llama3:8b
   ```
   Sofern du ein anderes Modell nutzen möchtest, passe `OLLAMA_MODEL` in der Umgebung an.

4. **Repo-Struktur prüfen**
   ```bash
   pct exec 10060 -- ls -1 /srv/ralf
   ```
   Erwartet werden u. a. die Ordner `automation`, `docs`, `tests` und `ci`.

## Nutzung
### Lokal (Ollama)
```bash
pct exec 10060 -- ralf-ai /srv/ralf --message "Starte mit Task X"
```
Der Wrapper setzt automatisch:
- `OPENAI_API_BASE=http://localhost:11434/v1`
- `OPENAI_API_KEY=ollama`
- `OLLAMA_MODEL=llama3:8b`

### Cloud-Fallback
```bash
export OPENAI_API_BASE="https://api.openai.com/v1"
export OPENAI_API_KEY="sk-..."
pct exec 10060 -- ralf-ai /srv/ralf --message "Nutze Cloud-Fallback"
```
Entferne oder überschreibe die Variablen nach der Cloud-Nutzung.

## Troubleshooting
| Problem | Hinweise |
|---------|----------|
| Container startet nicht | `pct status 10060` prüfen. Bei Bedarf `pct start 10060` und Logs mit `journalctl -u pveproxy` ansehen. |
| Kein Netzwerk im Container | Bridge `vmbr0` kontrollieren, `pct exec 10060 -- ip a` ausführen, ggf. DHCP-Server prüfen. |
| Ollama antwortet nicht | `pct exec 10060 -- systemctl status ollama` und `pct exec 10060 -- systemctl restart ollama`. Modell erneut mit `ollama pull` laden. |
| Wrapper fehlt | `pct exec 10060 -- ls -l /usr/local/bin/ralf-ai` prüfen, Skript erneut über das Build-Skript provisionieren lassen. |
| Aider schlägt fehl | Sicherstellen, dass `python3-pip` installiert und `aider-chat` aktuell ist (`pct exec 10060 -- python3 -m pip install --upgrade aider-chat`). |

## Tests & Qualitätssicherung
Führe vor jedem Merge mindestens folgende Checks aus:
```bash
make lint
make test
```
`make lint` startet [`tests/shellcheck.sh`](../tests/shellcheck.sh), `make test` ruft die Smoke-Tests für Build-Skript und Wrapper auf.

## PR-Checkliste
- [ ] Dry-Run des Build-Skripts erfolgreich (`bash automation/ralf/build_local_ai_lxc.sh --dry-run`).
- [ ] Realer Lauf abgeschlossen (`sudo bash automation/ralf/build_local_ai_lxc.sh`).
- [ ] Modell `llama3:8b` über Ollama verfügbar (`pct exec 10060 -- ollama list`).
- [ ] Smoke-Tests grün (`make lint` & `make test`).
- [ ] Dokumentation aktualisiert (insbesondere diese Datei und das README).
- [ ] Merge-Ziel bestätigt: **Merge PR feature/local-ai-hybrid → main nach erfolgreichem Test**.

Bleibe bei allen Änderungen idempotent und halte Secrets außerhalb des Repositories.
