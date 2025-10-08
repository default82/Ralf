# Monitoring role

This role provisions a full monitoring stack consisting of Prometheus, Alertmanager, Grafana, and node-exporter using Docker Compose.

## Requirements

* Docker Engine on the managed host
* The `community.docker` collection available to the control node

## Role variables

| Variable | Default | Description |
|----------|---------|-------------|
| `monitoring_manage_user` | `true` | Create the configured service user and group. |
| `monitoring_manage_docker` | `true` | Run and manage the Docker Compose stack. |
| `monitoring_user` | `monitoring` | Service user owning configuration and data directories. |
| `monitoring_group` | `monitoring` | Service group owning configuration and data directories. |
| `monitoring_base_dir` | `/opt/monitoring` | Base directory for the monitoring stack. |
| `monitoring_config_dir` | `${monitoring_base_dir}/config` | Configuration root directory. |
| `monitoring_data_dir` | `${monitoring_base_dir}/data` | Data directory root. |
| `monitoring_runtime_dir` | `${monitoring_base_dir}/run` | Runtime directory for generated files/logs. |
| `monitoring_prometheus_data_dir` | `${monitoring_data_dir}/prometheus` | Prometheus TSDB storage path. |
| `monitoring_alertmanager_data_dir` | `${monitoring_data_dir}/alertmanager` | Alertmanager state storage. |
| `monitoring_grafana_data_dir` | `${monitoring_data_dir}/grafana` | Grafana data storage. |
| `monitoring_prometheus_image` | `prom/prometheus:v2.49.1` | Prometheus container image. |
| `monitoring_alertmanager_image` | `prom/alertmanager:v0.27.0` | Alertmanager container image. |
| `monitoring_grafana_image` | `grafana/grafana:10.4.0` | Grafana container image. |
| `monitoring_node_exporter_image` | `prom/node-exporter:v1.7.0` | node-exporter container image. |
| `monitoring_prometheus_port` | `9090` | Published port for Prometheus. |
| `monitoring_alertmanager_port` | `9093` | Published port for Alertmanager. |
| `monitoring_grafana_port` | `3000` | Published port for Grafana. |
| `monitoring_node_exporter_port` | `9100` | Published port for node-exporter. |
| `monitoring_prometheus_scrape_interval` | `15s` | Global Prometheus scrape interval. |
| `monitoring_prometheus_evaluation_interval` | `15s` | Global Prometheus rule evaluation interval. |
| `monitoring_prometheus_alertmanager_targets` | `['alertmanager:9093']` | List of Alertmanager targets for Prometheus. |
| `monitoring_prometheus_node_exporter_targets` | `['node-exporter:9100']` | List of node-exporter targets for Prometheus. |
| `monitoring_prometheus_additional_scrape_configs` | `[]` | Additional scrape configurations appended to `scrape_configs`. |
| `monitoring_prometheus_rule_files` | `[]` | List of rule files referenced by Prometheus. |
| `monitoring_alertmanager_route` | `{ receiver: 'default' }` | Base routing definition for Alertmanager. |
| `monitoring_alertmanager_receivers` | `[ { name: 'default', webhook_configs: [] } ]` | Receiver definitions for Alertmanager. |
| `monitoring_grafana_admin_user` | `admin` | Initial Grafana admin user. |
| `monitoring_grafana_admin_password` | `admin` | Initial Grafana admin password (change in production!). |
| `monitoring_grafana_server_domain` | `localhost` | Grafana server domain. |
| `monitoring_grafana_server_root_url` | `%(protocol)s://%(domain)s:%(http_port)s/` | Grafana root URL format. |
| `monitoring_grafana_security_disable_gravatar` | `true` | Disable Gravatar in Grafana. |
| `monitoring_grafana_auth_anonymous_enabled` | `false` | Allow anonymous Grafana access. |
| `monitoring_compose_project_name` | `monitoring` | Docker Compose project name. |
| `monitoring_compose_file` | `${monitoring_base_dir}/docker-compose.yml` | Location of the generated Compose file. |
| `monitoring_compose_pull` | `false` | Pull images during the Compose run. |
| `monitoring_prometheus_container_user` | `"0:0"` | Container user specification for Prometheus. |
| `monitoring_alertmanager_container_user` | `"0:0"` | Container user specification for Alertmanager. |
| `monitoring_grafana_container_user` | `"0:0"` | Container user specification for Grafana. |
| `monitoring_node_exporter_container_user` | `"0:0"` | Container user specification for node-exporter. |

Additional variables can be set to fine-tune the generated templates by overriding the defaults in `defaults/main.yml`.

## Handlers

Handlers are defined to restart individual services whenever their respective configuration files change.

## Molecule

A Molecule scenario is available under `molecule/default` for linting and syntax validation of the role.

## Example playbook

```yaml
- hosts: monitoring
  roles:
    - role: monitoring
      vars:
        monitoring_grafana_admin_password: "super-secret"
```
