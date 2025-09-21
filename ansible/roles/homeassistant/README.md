# Home Assistant role

The Home Assistant role builds the configuration skeleton consumed by the dedicated Home Assistant LXC/VM.

## Features

* Creates the configuration directory and renders `configuration.yaml` from declarative integration metadata.
* Manages `secrets.yaml`, allowing sensitive values to remain sourced from SOPS-encrypted vars while keeping plaintext on disk minimal.
* Supports toggling integrations and automations directly from inventory variables.

## Variables

| Variable | Description |
| --- | --- |
| `homeassistant_config_dir` | Destination for rendered Home Assistant configuration. |
| `homeassistant_http` | HTTP settings (base URL, proxy support). |
| `homeassistant_integrations` | List of integrations and options to enable. |
| `homeassistant_automations` | Optional automation definitions appended to the config. |
| `homeassistant_secrets` | Mapping written to `secrets.yaml`. |

Extend `defaults/main.yml` with your actual integrations and secrets (kept encrypted upstream).
