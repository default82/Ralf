# BACKUPS role

This role configures the backups service stack for the RALF platform.

## TODO
- [ ] Provision the backup orchestrator (restic/borg) targeting the secure storage class with encryption.
- [ ] Define job schedules per service LXC and test restores into disposable containers.
- [ ] Publish backup compliance reports to the portal and monitoring stack.

See [docs/TODO.md](../../../docs/TODO.md#backups-role) for the authoritative backlog.
