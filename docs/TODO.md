# RALF Backlog

This document collects the outstanding work items across the RALF stack so they can be prioritised centrally. Each section mirrors the TODO snippets that live with the relevant component README files. Lists are ordered so foundational work appears before follow-on items.

## Installer
- [ ] Add validation to reject invalid IP addresses, VLAN IDs, and CIDR combinations during the interactive run.
- [ ] Support exporting host variable overrides (CPU, memory, storage class) alongside the generated inventory.
- [ ] Offer non-interactive mode fed via environment variables or a YAML answer file for GitOps use.

## Portal
- [ ] Scaffold a static UI build pipeline that renders the service catalogue from inventory data.
- [ ] Add authentication middleware that delegates to the central auth LXC.
- [ ] Surface health status badges sourced from monitoring and backup reports.

## Ansible Roles

### Base role
- [ ] Harden Debian/Proxmox hosts (timezone, locale, sysctl, unattended-upgrades) for LXCs and hypervisors.
- [ ] Manage automation users/SSH keys and install baseline tooling (git, ansible, sops, python).
- [ ] Template GitOps runner systemd units/timers and enforce journald/logrotate policies.

### DNS role
- [ ] Deploy Unbound/Bind9 with forward/reverse zone templates for the homelab domain.
- [ ] Populate zone data from network manifests and regenerate zones on inventory updates.
- [ ] Expose Prometheus exporters and DNS health checks.

### Caddy role
- [ ] Render Caddyfile templates driven by inventory service FQDNs and internal backends.
- [ ] Persist ACME account data on secure storage and automate certificate renewals.
- [ ] Provide handlers to reload the proxy on configuration or certificate changes.

### Auth role
- [ ] Deploy the chosen IdP (Keycloak/Authelia) with an external database and persistent storage bindings.
- [ ] Seed initial realms/users/groups that align with homelab personas.
- [ ] Integrate OIDC/SAML clients for portal, monitoring, and backup services.

### Monitoring role
- [ ] Roll out Prometheus/Grafana stack with long-term retention on the bulk pool.
- [ ] Enable Alertmanager routing to the configured monitoring contact.
- [ ] Configure exporters, LXC scrape jobs, and synthetic health checks.

### Backups role
- [ ] Provision the backup orchestrator (restic/borg) targeting the secure storage class with encryption.
- [ ] Define job schedules per service LXC and test restores into disposable containers.
- [ ] Publish backup compliance reports to the portal and monitoring stack.

### Vaultwarden role
- [ ] Containerise Vaultwarden with persistent storage, secrets management, and SMTP integration.
- [ ] Automate admin token rotation and encrypted backups of the database.
- [ ] Provide health probes and ingress metadata for the reverse proxy.

### Mail role
- [ ] Extend Postfix deployment with spam filtering, DKIM/DMARC signing, and monitoring hooks.
- [ ] Parameterise relay host credentials and manage secrets securely.
- [ ] Document mailbox provisioning and service integrations.

### Home Assistant role
- [ ] Deploy Home Assistant with required USB/IP passthrough policies and persistent storage.
- [ ] Integrate MQTT broker plus InfluxDB/Grafana dashboards for telemetry.
- [ ] Automate snapshot exports to the secure backup target.
