# Caddy role

The Caddy role assembles the reverse proxy configuration used to front the homelab services.

## Features

* Prepares configuration, data, and ACME directories for the Caddy deployment.
* Renders a declarative `Caddyfile` from inventory-driven site definitions, including TLS policy and security headers.
* Stores a machine-readable `sites.yaml` summary to power the portal UI or GitOps diff tooling.

## Variables

| Variable | Description |
| --- | --- |
| `caddy_config_dir` | Destination for the generated `Caddyfile`. |
| `caddy_data_dir` | Directory that will back Caddy's data volume (certificates, state). |
| `caddy_acme_dir` | Directory reserved for ACME cache material. |
| `caddy_global_options` | Global Caddy settings (support email, ports, auto HTTPS toggle). |
| `caddy_sites` | List of site dictionaries containing hostnames, upstreams, TLS options, and optional headers. |
| `caddy_additional_snippets` | Extra Caddyfile fragments appended verbatim. |

See `defaults/main.yml` for examples and adjust to match your service inventory.
