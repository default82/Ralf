# Mail role

The mail role prepares a relay-only Postfix configuration used to deliver notifications for RALF services.

## Features

* Creates configuration and queue directories owned by the Postfix service account.
* Renders `main.cf` with TLS-enforced relay settings, SASL credentials, and trusted network allowances.
* Produces SASL password and virtual alias maps along with a YAML export of trusted networks for documentation.

## Variables

| Variable | Description |
| --- | --- |
| `mail_config_dir` | Directory where Postfix configuration files are generated. |
| `mail_queue_dir` | Queue directory for spool data. |
| `mail_relay_host` / `mail_relay_port` | Upstream relay endpoint. |
| `mail_relay_username` / `mail_relay_password_file` | Credentials for authenticated relay. |
| `mail_virtual_aliases` | Mapping of virtual addresses to real recipients. |
| `mail_trusted_networks` | Networks allowed to submit mail without auth. |
| `mail_tls_policy` | TLS policy for outbound SMTP. |

Update `defaults/main.yml` with the real relay host, credentials, and alias mapping.
