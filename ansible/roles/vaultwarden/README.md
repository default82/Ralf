# Vaultwarden role

This role deploys the Vaultwarden password manager as a Docker based service,
configures backups and optional TLS termination, and wires the instance into the
RALF secrets workflow.

## Features
- Deploys a self-contained `docker-compose.yml` project executed via
  `systemd` (`vaultwarden.service`).
- Manages configuration (`config.json`) and `.env` file rendering from
  declarative variables.
- Provides automated backups with retention through
  `vaultwarden-backup.service` and `vaultwarden-backup.timer`.
- Supports inline TLS secrets or reuse of existing certificate/key files for
  end-to-end HTTPS.

## Requirements
- Docker Engine with Compose plugin (`/usr/bin/docker compose`).
- A reachable PostgreSQL instance as configured via the database defaults.
- A secrets backend (e.g. `.env`, HashiCorp Vault, Ansible Vault) providing
  the administrator token and database password.

## Role variables
Important defaults from [`defaults/main.yml`](defaults/main.yml):

| Variable | Description | Default |
| --- | --- | --- |
| `vaultwarden_http_port` | Published HTTP port on the host | `10301` |
| `vaultwarden_internal_port` | Port inside the container | `80` |
| `vaultwarden_database_url` | Derived PostgreSQL connection string | built from DB defaults |
| `vaultwarden_admin_token` | Admin panel token, injected from secrets | empty → must be provided |
| `vaultwarden_enable_ssl` | Enable TLS inside the container | `false` |
| `vaultwarden_backup_retention` | Number of backup archives to keep | `7` |
| `vaultwarden_backup_oncalendar` | Systemd timer schedule | `daily` |

The full set of variables is documented inline in the defaults file. Extend the
environment or Compose configuration via `vaultwarden_env_overrides`,
`vaultwarden_secret_env`, `vaultwarden_additional_ports`,
`vaultwarden_additional_volumes` and `vaultwarden_compose_extra`.

### Secrets flow integration
Secrets are sourced from environment variables or a secrets backend. The role
expects the following sensitive values:

- `VAULTWARDEN_DB_PASSWORD`
- `VAULTWARDEN_ADMIN_TOKEN`

During development or on air-gapped systems you can copy
[`.env.example`](../../../.env.example) and augment it with these variables. When
using a dedicated secret backend, map the retrieved values to the Ansible
variables `vaultwarden_db_password` and `vaultwarden_admin_token` (for example
via `ansible-vault`, `hashi_vault`, SOPS, etc.). The role renders
`vaultwarden.env` from the combined dictionary so no secrets are committed to
version control.

### TLS handling
Set `vaultwarden_enable_ssl: true` to mount certificates inside the container.
Either provide existing files on the managed host or pass the PEM content via
`vaultwarden_ssl_certificate` / `vaultwarden_ssl_private_key` which will be
written to `vaultwarden_ssl_certificate_file` and
`vaultwarden_ssl_private_key_file` respectively.

### Backups
Backups are stored in `vaultwarden_backup_dir` and rotated according to
`vaultwarden_backup_retention`. Adjust `vaultwarden_backup_oncalendar` to change
the execution frequency.

## Molecule
A Molecule scenario (`molecule/default`) validates template rendering and
idempotency. Execute it locally via:

```bash
cd ansible/roles/vaultwarden
molecule test
```

Use `vaultwarden_manage_systemd: false` when running on platforms without
systemd support.
