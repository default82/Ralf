# RALF Backlog

This document collects the outstanding work items across the RALF stack so they can be prioritised centrally. Each section mirrors the TODO snippets that live with the relevant component README files.

## Installer
- [ ] Add validation to reject invalid IP addresses, VLAN IDs, and CIDR combinations during the interactive run.
- [ ] Support exporting host variable overrides (CPU, memory, storage class) alongside the generated inventory.
- [ ] Offer non-interactive mode fed via environment variables or a YAML answer file for GitOps use.

## Portal
- [ ] Scaffold a static UI (Next.js or Astro) that renders the service catalogue from inventory metadata.
- [ ] Add authentication middleware that delegates to the central auth LXC (Keycloak/Authelia).
- [ ] Wire up health status badges sourced from Prometheus and backup verification reports.

## Ansible Roles

### Base role
- [ ] Harden Debian/Proxmox hosts (timezone, locale, sysctl, unattended-upgrades) for both LXCs and the hypervisor.
- [ ] Manage automation users/SSH keys and ship baseline tooling (git, ansible, sops, python).
- [ ] Template GitOps runner units/timers and ensure journald/logrotate policies are enforced.

### DNS role
- [ ] Deploy Unbound/Bind9 packages and lay down forward/reverse zone templates for the homelab domain.
- [ ] Populate zone data from `network/vlan-plan.yaml` and regenerate zones on inventory changes.
- [ ] Expose Prometheus exporters/health checks for DNS reachability.

### Caddy role
- [ ] Render Caddyfile templates driven by inventory service FQDNs and internal backends.
- [ ] Store ACME account data on the secure storage class and rotate certificates automatically.
- [ ] Provide handlers to reload the proxy on configuration or certificate changes.

### Auth role
- [ ] Deploy the chosen IdP (Keycloak/Authelia) with an external database and persistent storage bindings.
- [ ] Seed initial realms/users/groups that align with homelab personas.
- [ ] Integrate OIDC/SAML clients for portal, monitoring, and backup services.

### Monitoring role
- [ ] Roll out Prometheus/Grafana stack with long-term retention on the `bulk` pool.
- [ ] Enable alerting via Alertmanager and route incidents to the configured monitoring contact.
- [ ] Configure node exporters, LXC scrape jobs, and synthetic health checks.

### Backups role
- [ ] Provision backup orchestrator (restic/borg) targeting the `secure` storage class with encryption.
- [ ] Define job schedules for each service LXC and test restores into disposable containers.
- [ ] Publish backup reports to the portal and monitoring systems.

### Vaultwarden role
- [ ] Containerise Vaultwarden with persistent storage, secrets management, and SMTP integration.
- [ ] Automate admin token rotation and backup of the SQLite database.
- [ ] Provide health probes and ingress labels for the reverse proxy.

### Mail role
- [ ] Extend beyond SMTP relay to cover spam filtering, DKIM/DMARC signing, and monitoring hooks.
- [ ] Parameterise relay host credentials and encrypted secret handling.
- [ ] Document mailbox provisioning workflow for downstream services.

### Home Assistant role
- [ ] Deploy Home Assistant container with USB/IP device passthrough policies.
- [ ] Integrate MQTT broker and InfluxDB/Grafana dashboards for sensor data.
- [ ] Automate snapshot exports to the secure backup target.
