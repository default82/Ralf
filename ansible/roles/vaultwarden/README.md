# Vaultwarden role

The Vaultwarden role materialises configuration for the Bitwarden-compatible password manager container.

## Features

* Creates configuration and data directories consumed by the Vaultwarden deployment.
* Renders an `.env` file with domain, admin token, and SMTP parameters sourced from inventory/secret files.
* Exports SMTP settings separately to simplify auditing and secret management.

## Variables

| Variable | Description |
| --- | --- |
| `vaultwarden_config_dir` | Directory for generated configuration artefacts. |
| `vaultwarden_data_dir` | Persistent storage directory mounted into the container. |
| `vaultwarden_env` | Environment variables rendered to `.env`. |
| `vaultwarden_smtp` | Structured SMTP configuration persisted as YAML. |
| `vaultwarden_admin_token_file` | Path to the admin token (referenced but not created). |

Ensure sensitive files referenced in `defaults/main.yml` are supplied via SOPS/age secrets.
