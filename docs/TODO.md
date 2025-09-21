# RALF Backlog


## Installer
- [ ] Add validation to reject invalid IP addresses, VLAN IDs, and CIDR combinations during the interactive run.
- [ ] Support exporting host variable overrides (CPU, memory, storage class) alongside the generated inventory.
- [ ] Offer non-interactive mode fed via environment variables or a YAML answer file for GitOps use.

## Portal


## Ansible Roles

### Base role

- [ ] Provide handlers to reload the proxy on configuration or certificate changes.

### Auth role
- [ ] Deploy the chosen IdP (Keycloak/Authelia) with an external database and persistent storage bindings.
- [ ] Seed initial realms/users/groups that align with homelab personas.
- [ ] Integrate OIDC/SAML clients for portal, monitoring, and backup services.

### Monitoring role

- [ ] Automate snapshot exports to the secure backup target.
