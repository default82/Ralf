# BASE role

This role configures the baseline service stack for the RALF platform.

## Features
- Installs a curated set of base packages plus any additional packages
  provided via `base_additional_packages`.
- Keeps the APT cache warm and configures automatic unattended upgrades.
- Optionally manages the system timezone and ensures `systemd-timesyncd`
  is enabled on systemd-based hosts.

## Default variables
| Variable | Default | Description |
|----------|---------|-------------|
| `base_supported_os_families` | `["Debian"]` | List of supported OS families. |
| `base_packages` | see defaults | Base packages to ensure are present. |
| `base_additional_packages` | `[]` | Extra packages appended to the base list. |
| `base_apt_cache_valid_time` | `3600` | Cache validity window (seconds) for `apt update`. |
| `base_manage_timezone` | `true` | Whether to enforce the timezone configured in `base_timezone`. |
| `base_timezone` | `Europe/Berlin` | Target system timezone. |
| `base_manage_timesyncd` | `true` | Enable and start `systemd-timesyncd` when available. |
| `base_manage_apt_periodic` | `true` | Render `/etc/apt/apt.conf.d/20auto-upgrades` from the provided settings. |
| `base_apt_periodic_settings` | see defaults | Key/value map rendered into `20auto-upgrades`. |

## Handlers
No custom handlers are required at the moment.

## Usage
```yaml
- hosts: all
  roles:
    - role: base
      vars:
        base_timezone: Europe/Berlin
        base_additional_packages:
          - net-tools
```
