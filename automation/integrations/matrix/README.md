# Matrix Synapse Webhook Examples

`synapse-webhook-modules.yaml` documents how to forward structured Synapse
notifications to the n8n automation engine. The configuration enables a webhook
module that signs requests with a shared secret stored in Vaultwarden and maps
custom event types to dedicated Matrix rooms.

Import the matching n8n workflow from `../n8n/matrix-incident-bridge.json` to
process the webhook payloads and fan them out to the homeserver.
