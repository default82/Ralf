# n8n Workflows

The workflows in this directory can be imported into n8n via "Import from file".
`matrix-incident-bridge` exposes a webhook that accepts incident payloads and
relays them to Matrix using tokens sourced from Vaultwarden. Environment
variables used by the workflow:

- `MATRIX_BASE_URL` – Homeserver URL, e.g. `https://matrix.homelab.lan`
- `MATRIX_ROOM_ID` – Default room receiving incident notifications
- `MATRIX_ACCESS_TOKEN` – Access token with permission to send messages

Override any of these values by including keys with the same name in the webhook
payload.
