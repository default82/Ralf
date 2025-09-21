# Auth role

The auth role prepares Authelia configuration for central authentication and MFA enforcement.

## Features

* Creates configuration and secret directories owned by the Authelia service account.
* Generates a complete `configuration.yml` covering LDAP identity provider settings, session policy, and access rules.
* Stores notifier parameters separately to simplify secret templating and SMTP credential injection.

## Variables

| Variable | Description |
| --- | --- |
| `auth_service_user` / `auth_service_group` | System identity owning Authelia artefacts. |
| `auth_config_dir` | Destination for the generated `configuration.yml`. |
| `auth_secrets_dir` | Directory holding password files referenced in the configuration. |
| `auth_identity_backend` | LDAP endpoint and bind credentials configuration. |
| `auth_access_control` | List of access-control rules applied per domain/resource. |
| `auth_session` | Session cookie parameters. |
| `auth_notifier` | Notifier transport definition (SMTP by default). |
| `auth_totp` | TOTP issuer metadata. |

Update `defaults/main.yml` to reflect your directory tree, domains, or notifier.
