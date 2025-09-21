# MAIL role

This role installs and configures the Postfix SMTP service for the RALF platform.

## Default behaviour
- Installs the packages defined in `mail_packages` (defaults to Postfix).
- Ensures supporting directories exist before configuration templates are deployed.
- Renders `/etc/postfix/main.cf` from `templates/main.cf.j2` using defaults that
  work for a simple relay-less setup.
- Optionally manages `/etc/aliases` (enabled by default) and rebuilds the alias
  database when it changes.
- Enables and starts the Postfix service.

## Variables
Key variables can be overridden as needed:

- `mail_hostname`, `mail_domain`, `mail_myorigin` – identity used in `main.cf`.
- `mail_relayhost` – upstream relay (empty string keeps local delivery).
- `mail_main_cf_extra_parameters` – dictionary of additional `main.cf` key/value pairs.
- `mail_aliases` – list of extra aliases beyond the managed `root` alias.
- `mail_service_enabled`, `mail_service_state` – service management flags.

See `defaults/main.yml` for the complete list of tunables.
