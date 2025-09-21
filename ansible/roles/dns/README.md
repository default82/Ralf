# DNS role

The DNS role provisions the CoreDNS configuration artefacts consumed by the RALF network stack.

## Features

* Creates dedicated configuration and runtime directories with the correct ownership for the CoreDNS service account.
* Generates a manifest describing listener settings, upstream resolvers, logging, and metrics exposure to aid GitOps diffing.
* Serialises forward and reverse zone definitions as YAML so they can be rendered into container images or templates later in the pipeline.

## Variables

| Variable | Description |
| --- | --- |
| `dns_service_user` / `dns_service_group` | System identity owning the CoreDNS config tree. |
| `dns_config_dir` | Persistent configuration directory (defaults to `/var/lib/ralf/dns`). |
| `dns_runtime_dir` | Writable runtime directory for sockets/cache data. |
| `dns_manifest` | Dictionary describing listener properties and upstream resolvers. |
| `dns_zones` | List of zones with record definitions, serialised into `zones/<zone>.yaml`. |
| `dns_zone_mode` | File extension to use for rendered zone data (`yaml` by default). |

Adjust the defaults in `defaults/main.yml` to match your domain structure or to supply different upstream resolvers.
