# R.A.L.F. LLM-Adapter

Der LLM-Adapter verbindet R.A.L.F. mit internen oder externen Sprachmodellen. Er stellt eine einheitliche REST- und gRPC-
Schnittstelle bereit, verarbeitet Rate-Limits pro Upstream und bezieht API-Keys direkt aus Vaultwarden.

## Features

- **REST (`/v1/generate`) und gRPC (`ralf.adapter.v1.LLMAdapter/Generate`)** nutzen denselben Service-Layer.
- **Vaultwarden-Integration:** `vault://`-Referenzen in der Konfiguration werden beim Laden gegen Vaultwarden aufgelöst.
- **Rate-Limiting pro Endpoint** mittels Token-Bucket.
- **Mehrere Backends** (OpenAI-kompatibel oder generisch) lassen sich parallel definieren.

## Konfiguration

Die Konfiguration wird als YAML-Datei geladen (z. B. `/etc/ralf/llm-adapter.yaml`). Ein Minimalbeispiel:

```yaml
default_endpoint: openai
vaultwarden:
  url: https://vault.lab.local
  access_token: env://RALF_VAULTWARDEN_TOKEN
endpoints:
  openai:
    url: https://api.openai.com/v1/chat/completions
    protocol: openai
    model: gpt-4o-mini
    rate_limit:
      requests_per_minute: 30
    auth:
      type: bearer
      token: vault://llm/openai/api-token
  local-ollama:
    url: http://llm-gateway.lab.local/v1/generate
    protocol: generic
    parameters:
      temperature: 0.2
    headers:
      X-API-Key: vault://llm/ollama/field:api-key
```

### Schlüsselelemente

- `default_endpoint`: Name des Standardendpunkts für Aufrufe ohne `endpoint`-Angabe.
- `vaultwarden`:
  - `url`: Basis-URL des Vaultwarden-Servers.
  - `access_token`: Zugriffstoken oder `env://`-Referenz auf eine Umgebungsvariable.
- `endpoints.<name>`:
  - `url`: Ziel-URL (HTTP/HTTPS).
  - `protocol`: `openai` für Chat-Completions, `generic` für freie POST-Endpunkte.
  - `model`: Optionales Default-Modell.
  - `parameters`: Default-Parameter (werden mit Request-Parametern gemerged).
  - `headers`: Zusätzliche HTTP-Header; Werte können `vault://`-Referenzen sein.
  - `auth`: Unterstützt `bearer`, `basic` oder `header` und nutzt optional Vaultwarden-Referenzen.
  - `rate_limit.requests_per_minute`: Maximale Requests pro Minute.

### Secret-Referenzen

`vault://<cipher>/<field>` referenziert einen Vaultwarden-Eintrag. `field:<name>` greift auf ein Custom-Field zu. Beispiel:

- `vault://llm/openai/api-token` → Login-Passwort.
- `vault://llm/ollama/field:api-key` → Custom Field `api-key`.

`env://VAR_NAME` liest Secrets aus Umgebungsvariablen (z. B. Vaultwarden Access Token).

## Starten der Services

### REST

```bash
uvicorn ralf_adapter.rest:create_app --factory --port 8000 --reload \
  --env-file /etc/ralf/adapter.env
```

`adapter.env` sollte `RALF_VAULTWARDEN_TOKEN=<token>` enthalten, falls `env://` verwendet wird.

### gRPC

```python
import asyncio
from pathlib import Path

from ralf_adapter.config import AdapterConfig
from ralf_adapter.grpc_server import serve

async def main() -> None:
    config = AdapterConfig.from_path(Path("/etc/ralf/llm-adapter.yaml"))
    await serve(config, host="0.0.0.0", port=50051)

asyncio.run(main())
```

## REST-API

`POST /v1/generate`

| Feld       | Typ                 | Beschreibung                                           |
| ---------- | ------------------- | ------------------------------------------------------ |
| `prompt`   | `string`            | Nutzerprompt / Frage                                  |
| `endpoint` | `string` (optional) | Zielendpunkt; Standard laut Konfiguration             |
| `model`    | `string` (optional) | Überschreibt das Defaultmodell                        |
| `parameters` | `object` (optional) | Zusätzliche Upstream-Parameter                      |
| `messages` | `array` (optional)  | Chat-Historie (nur OpenAI-kompatible Backends)        |
| `metadata` | `object` (optional) | Wird unverändert an den Upstream gesendet             |

Antwort:

```json
{
  "text": "Antwort des Modells",
  "model": "gpt-4o-mini",
  "endpoint": "openai",
  "latency_ms": 842,
  "usage": {"prompt_tokens": 42},
  "raw": {...}
}
```

Fehlerstatus:

- `429` – Rate-Limit erreicht.
- `502` – Fehler beim Upstream oder ungültige Antwort.

## gRPC-Service

Service-Name: `ralf.adapter.v1.LLMAdapter`

RPC: `Generate(struct)`

- Erwartet Felder analog zum REST-Body (`prompt`, `endpoint`, `model`, `parameters`, `messages`, `metadata`).
- Antwort: `Struct` mit Feldern `text`, `endpoint`, `model`, `latency_ms`, `usage`, `raw`.

Fehlercodes:

- `INVALID_ARGUMENT` – `prompt` fehlt oder leer.
- `RESOURCE_EXHAUSTED` – Rate-Limit verletzt.
- `FAILED_PRECONDITION` – Upstream-Fehler (z. B. Auth, ungültige Antwort).

## Beispielaufrufe

REST (`curl`):

```bash
curl -X POST http://adapter01.lab.local:8000/v1/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Summiere 3+4", "endpoint":"local-ollama"}'
```

gRPC (`grpcurl`):

```bash
grpcurl -plaintext -d '{"prompt":"Statusbericht für Ralf"}' \
  adapter01.lab.local:50051 ralf.adapter.v1.LLMAdapter/Generate
```

## Rate-Limiting

- Implementiert als Token-Bucket; `requests_per_minute` legt Kapazität und Füllrate fest.
- REST und gRPC teilen sich dieselben Buckets, da sie auf denselben Service zugreifen.
- Bei Überschreitung wird der Aufruf mit `429` (REST) bzw. `RESOURCE_EXHAUSTED` (gRPC) abgewiesen.

## Vaultwarden-Berechtigungen

- Der Adapter benötigt ein Vaultwarden-Token mit Lesezugriff auf die referenzierten Ciphers.
- Secrets werden beim Laden aufgelöst; nach Rotation sollte der Service neu geladen werden.
- Für langlaufende Deployments empfiehlt sich eine Rotation via Installer (`configure_llm_adapter`).

## Troubleshooting

1. **HTTP 502 / FAILED_PRECONDITION:** Upstream-URL, Auth-Header oder Modellnamen prüfen.
2. **Vault-Fehler:** Stellen Sie sicher, dass das Vaultwarden-Token gültig ist und die Ciphers sichtbar sind.
3. **Leere Antwort:** Überprüfen, ob das Zielprotokoll korrekt (openai/generic) gesetzt ist.
