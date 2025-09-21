# Vaultwarden Secret Helper

`fetch_secret.sh` wraps the Bitwarden CLI (`bw`) to pull tokens that power n8n
and Matrix automations. It supports both API-key and unlocked-session flows and
prints the requested field to STDOUT so it can be piped directly into
configuration templates.

Example:

```bash
export VAULTWARDEN_URL=https://vaultwarden.homelab.lan
export BW_CLIENTID=... # from Vaultwarden
export BW_CLIENTSECRET=...
export BW_PASSWORD=super-secure
export VAULTWARDEN_ITEM=n8n-matrix-token
export VAULTWARDEN_FIELD=password
secret=$(./fetch_secret.sh)
```
