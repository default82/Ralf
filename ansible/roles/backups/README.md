# Backups role

The backups role renders repository metadata, retention policy, and helper scripts for the encrypted Restic-based backup flow.

## Features

* Creates configuration, script, and log directories for the backup orchestrator.
* Serialises repository definitions (target path, include/exclude sets, schedules) to `repositories.yaml`.
* Generates an idempotent shell wrapper that iterates over repositories, runs backups, enforces retention, and optionally pings a healthcheck endpoint.

## Variables

| Variable | Description |
| --- | --- |
| `backups_config_dir` | Configuration directory, defaults to `/var/lib/ralf/backups`. |
| `backups_scripts_dir` | Output path for generated helper scripts. |
| `backups_log_dir` | Directory for log capture. |
| `backups_repositories` | List of repositories with include/exclude paths and schedules. |
| `backups_retention` | Retention window (daily/weekly/monthly) enforced by the wrapper script. |
| `backups_healthchecks` | Optional healthchecks.io-style endpoint toggled via `enabled`. |
| `backups_command` | Backup binary to invoke (defaults to `restic`). |

Secrets (like repository passwords) are referenced by path and should be managed via SOPS/age.
