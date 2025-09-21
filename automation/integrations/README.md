# Integration Automations

This directory bundles reference automations that connect the n8n workflow
engine with Matrix Synapse and Vaultwarden secrets. Each subdirectory includes
self-contained examples that can be imported into n8n or referenced by
Ansible/Vaultwarden playbooks.

## Contents

- `n8n/` – exportable n8n workflows that transform inbound webhooks into Matrix
  notifications and support secret lookups.
- `matrix/` – Synapse modules and webhook examples used to forward events to
  n8n or other automation targets.
- `vaultwarden/` – helper scripts for retrieving credentials from the
  Vaultwarden Bitwarden-compatible API via the `bw` CLI.

The examples are intentionally lightweight; adjust paths, room IDs and hosts to
match the homelab topology before deploying to production.
