# RALF – Lokale AI-Assistenz auf Proxmox

Merge PR feature/local-ai-hybrid → main nach erfolgreichem Test

## Überblick
- **Container**: `lisa-llm` (VMID `10060`) auf Proxmox `pve01`, erstellt durch [`automation/ralf/build_local_ai_lxc.sh`](automation/ralf/build_local_ai_lxc.sh).
- **Persistenz**: Host-Verzeichnis `/srv/ralf` wird in den Container gemountet und enthält sämtlichen Repo-Inhalt.
- **Inference**: Ollama stellt `llama3:8b` lokal bereit; der Wrapper [`automation/ralf/rlwrap/ralf-ai.sh`](automation/ralf/rlwrap/ralf-ai.sh)
  konfiguriert Aider gegen diesen Endpoint oder – via Umgebungsvariablen – gegen eine OpenAI-kompatible Cloud.
- **Dokumentation**: Ausführliche Schritte stehen im [Local AI Hybrid Guide](docs/LOCAL_AI_README.md).

## Schnellstart
```bash
bash automation/ralf/build_local_ai_lxc.sh --dry-run
sudo bash automation/ralf/build_local_ai_lxc.sh
pct exec 10060 -- ollama pull llama3:8b
pct exec 10060 -- ralf-ai /srv/ralf --message "Starte mit Task X"
```

## Tests & Qualitätssicherung
```bash
make lint
make test
```
- `make lint` nutzt [`tests/shellcheck.sh`](tests/shellcheck.sh).
- `make test` führt [`tests/smoke_build_lxc.sh`](tests/smoke_build_lxc.sh) und [`tests/smoke_wrapper.sh`](tests/smoke_wrapper.sh) aus.

## Cloud-Fallback
Setze temporär die OpenAI-Variablen, um denselben Wrapper gegen einen externen Dienst zu richten:
```bash
export OPENAI_API_BASE="https://api.openai.com/v1"
export OPENAI_API_KEY="sk-..."
pct exec 10060 -- ralf-ai /srv/ralf --message "Cloud-Fallback"
```

## CHANGELOG
- **2024-05-08**: Hybrid-Container-Skript, Wrapper, Smoke-Tests und Dokumentation aktualisiert.
