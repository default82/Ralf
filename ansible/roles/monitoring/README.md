# Monitoring role

The monitoring role prepares Prometheus, Alertmanager, and Grafana dashboard metadata for the observability stack.

## Features

* Creates directories for Prometheus configuration, custom alerting rules, and dashboard exports.
* Renders `prometheus.yml` and `alertmanager.yml` based on inventory-driven scrape targets and routing policies.
* Tracks dashboard metadata and recording rules in YAML to drive downstream provisioning (e.g., Grafana API imports).

## Variables

| Variable | Description |
| --- | --- |
| `monitoring_config_dir` | Root configuration directory (default `/var/lib/ralf/monitoring`). |
| `monitoring_prometheus_global` | Prometheus global scrape/evaluation intervals. |
| `monitoring_prometheus_scrape_configs` | List of scrape jobs with targets and labels. |
| `monitoring_alertmanager_receivers` | Alertmanager receiver definitions (email, Matrix, webhooks). |
| `monitoring_alertmanager_route` | Root routing tree selecting receivers by severity/labels. |
| `monitoring_dashboards` | Dashboard metadata stored under `dashboards.yaml`. |
| `monitoring_recording_rules` | Additional recording rules recorded to `rules.yaml`. |

Consult `defaults/main.yml` for example values.
