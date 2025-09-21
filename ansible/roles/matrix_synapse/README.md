# Matrix Synapse role

The Matrix Synapse role assembles configuration artefacts for the Matrix homeserver, database connectivity, and ingress wiring.

## Features

* Creates configuration and media directories for the Synapse container or LXC.
* Renders `homeserver.yaml` with PostgreSQL settings, listener configuration, and TURN integration toggles.
* Records the deployed Synapse version, Caddy site definition, and administrative metadata (admin/bot/rooms) for GitOps review.

## Variables

| Variable | Description |
| --- | --- |
| `matrix_synapse_config_dir` / `matrix_synapse_media_dir` | Paths for configuration and media storage. |
| `matrix_synapse_server_name` / `matrix_synapse_public_baseurl` | Federation identity and public endpoint. |
| `matrix_synapse_postgres_*` | Database connectivity parameters and password file paths. |
| `matrix_synapse_registration_shared_secret_file` | Path to the shared secret used for self-service registration tooling. |
| `matrix_synapse_turn` | TURN configuration toggles and shared secret reference. |
| `matrix_synapse_caddy_site` | Reverse proxy definition exported for the Caddy role. |
| `matrix_synapse_admin_manifest` | Metadata persisted to `admin.yaml`, merged with `matrix_synapse_rooms`. |

See `defaults/main.yml` for a complete list of values and adjust them per environment.
