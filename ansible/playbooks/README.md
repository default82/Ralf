# Ansible Playbooks

The playbooks in this directory orchestrate the RALF platform. Highlights:

- `deploy-services.yaml` – deploys user-facing services such as Vaultwarden,
  Mail and Home Assistant.
- `site.yaml` – full platform bootstrap including infrastructure roles.

Run a targeted deployment, e.g. for Vaultwarden only:

```bash
ansible-playbook -i ../inventories/hosts.yaml deploy-services.yaml --limit vaultwarden
```

## Vaultwarden secrets
The Vaultwarden role consumes secrets from the same flow used by the rest of
RALF. Inject the values `VAULTWARDEN_DB_PASSWORD` and
`VAULTWARDEN_ADMIN_TOKEN` either via environment, `ansible-vault`, or an
external backend. See [`roles/vaultwarden/README.md`](../roles/vaultwarden/README.md)
and the repository-level [`.env.example`](../../.env.example) for the expected
variables.

## Testing
Molecule scenarios validate the roles. To test Vaultwarden locally:

```bash
cd ../roles/vaultwarden
molecule test
```
