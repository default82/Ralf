# BASE role

This role prepares every Proxmox host (and the LXCs it spawns) with a consistent RALF baseline.

## Features

* Creates the runtime, state, and configuration directories under `/srv/ralf`, `/var/lib/ralf`, and `/etc/ralf` so other roles can safely drop artefacts.
* Installs the common package toolchain (Python, Git, rsync, etc.) required by the automation stack and service roles.
* Applies opinionated sysctl defaults to enable IPv4 forwarding and tune swap aggressiveness for container-heavy workloads.
* Publishes a managed `/etc/motd.d/ralf` banner and shell aliases in `/etc/profile.d/ralf.sh` to highlight the GitOps ownership of the node.

## Variables

Key defaults live in `defaults/main.yml`:

| Variable | Description |
| --- | --- |
| `ralf_root_dir` | Base runtime directory for generated artefacts (`/srv/ralf` by default). |
| `ralf_state_dir` | Persistent state directory (`/var/lib/ralf`). |
| `ralf_config_dir` | Configuration anchor for generated files (`/etc/ralf`). |
| `base_packages` | Package list installed across all nodes. |
| `base_sysctl` | Mapping of sysctl keys to enforce (reloaded automatically). |
| `base_shell_aliases` | Aliases rendered into `/etc/profile.d/ralf.sh`. |
| `base_motd_header` | MOTD banner text informing operators about GitOps ownership. |

Override the defaults via inventory/group vars if you need custom paths or packages.
