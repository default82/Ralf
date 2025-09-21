# BASE role

This role configures the base service stack for the RALF platform.

## TODO
- [ ] Harden Debian/Proxmox hosts (timezone, locale, sysctl, unattended-upgrades) for LXCs and hypervisors.
- [ ] Manage automation users/SSH keys and install baseline tooling (git, ansible, sops, python).
- [ ] Template GitOps runner systemd units/timers and enforce journald/logrotate policies.

See [docs/TODO.md](../../../docs/TODO.md#base-role) for the authoritative backlog.
