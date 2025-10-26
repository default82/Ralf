"""Built-in task implementations shipped with the installer."""

from __future__ import annotations

from typing import Any

from ..execution.context import ExecutionContext
from .registry import registry


def _message(context: ExecutionContext, fallback: str) -> str:
    description = context.task.description.strip()
    if description:
        return description
    return fallback


def _target(context: ExecutionContext, *, default: str | None = None) -> str:
    target = context.task.parameters.get("target")
    if isinstance(target, str) and target:
        return target
    if default:
        return default
    return context.component.name


def _record_state(context: ExecutionContext, collection: str, value: Any) -> None:
    bucket = context.shared_state.setdefault(collection, [])
    bucket.append(value)


@registry.register("storage.prepare_volumes", summary="Prepare persistent volumes for a service", tags=("storage",))
def storage_prepare_volumes(context: ExecutionContext) -> None:
    service = _target(context)
    _record_state(context, "storage", {"service": service, "action": "prepare_volumes"})
    context.record(_message(context, f"Prepare storage volumes for {service}"))


@registry.register("postgresql.deploy_runtime", summary="Deploy PostgreSQL runtime", tags=("database",))
def postgresql_deploy_runtime(context: ExecutionContext) -> None:
    service = _target(context, default="postgresql")
    _record_state(context, "services", {"service": service, "action": "deploy"})
    context.record(_message(context, f"Deploy {service} runtime"))


@registry.register(
    "postgresql.configure_accounts",
    summary="Configure PostgreSQL accounts",
    tags=("database", "configuration"),
)
def postgresql_configure_accounts(context: ExecutionContext) -> None:
    service = _target(context, default="postgresql")
    accounts = context.task.parameters.get("accounts")
    if isinstance(accounts, list):
        _record_state(context, "database_accounts", {"service": service, "accounts": accounts})
    context.record(_message(context, f"Configure accounts for {service}"))


@registry.register("gitea.deploy_runtime", summary="Deploy Gitea service", tags=("git", "service"))
def gitea_deploy_runtime(context: ExecutionContext) -> None:
    service = _target(context, default="gitea")
    _record_state(context, "services", {"service": service, "action": "deploy"})
    context.record(_message(context, "Provision Gitea runtime and required volumes"))


@registry.register(
    "gitea.configure_database",
    summary="Configure Gitea database connection",
    tags=("git", "configuration"),
)
def gitea_configure_database(context: ExecutionContext) -> None:
    database = context.task.parameters.get("database")
    if isinstance(database, str) and database:
        _record_state(context, "service_bindings", {"service": "gitea", "database": database})
    context.record(_message(context, "Configure database connection credentials"))


@registry.register("gitea.seed_repositories", summary="Seed automation repositories", tags=("git", "bootstrap"))
def gitea_seed_repositories(context: ExecutionContext) -> None:
    repos = context.task.parameters.get("repositories")
    if isinstance(repos, list):
        _record_state(context, "repositories", repos)
    context.record(_message(context, "Seed repositories for automation and knowledge artifacts"))


@registry.register("vaultwarden.deploy_service", summary="Deploy Vaultwarden", tags=("secrets", "service"))
def vaultwarden_deploy_service(context: ExecutionContext) -> None:
    _record_state(context, "services", {"service": "vaultwarden", "action": "deploy"})
    context.record(_message(context, "Deploy Vaultwarden service"))


@registry.register(
    "vaultwarden.configure_admin",
    summary="Configure Vaultwarden admin account",
    tags=("secrets", "configuration"),
)
def vaultwarden_configure_admin(context: ExecutionContext) -> None:
    admin = context.task.parameters.get("admin_user", "admin")
    _record_state(context, "secrets_admin", {"service": "vaultwarden", "admin": admin})
    context.record(_message(context, "Configure admin account and secrets storage"))


@registry.register(
    "vaultwarden.sync_bootstrap_secrets",
    summary="Synchronise bootstrap secrets",
    tags=("secrets", "bootstrap"),
)
def vaultwarden_sync_bootstrap_secrets(context: ExecutionContext) -> None:
    targets = context.task.parameters.get("targets")
    if isinstance(targets, list):
        _record_state(context, "secret_targets", targets)
    context.record(_message(context, "Synchronise bootstrap secrets with installation nodes"))


@registry.register(
    "automation.deploy_opentofu",
    summary="Deploy OpenTofu execution environment",
    tags=("automation", "infrastructure"),
)
def automation_deploy_opentofu(context: ExecutionContext) -> None:
    context.record(_message(context, "Deploy OpenTofu execution environment"))
    _record_state(context, "automation", {"tool": "opentofu", "action": "deploy"})


@registry.register(
    "automation.deploy_ansible",
    summary="Deploy Ansible control node",
    tags=("automation", "configuration"),
)
def automation_deploy_ansible(context: ExecutionContext) -> None:
    context.record(_message(context, "Deploy Ansible control node"))
    _record_state(context, "automation", {"tool": "ansible", "action": "deploy"})


@registry.register(
    "automation.register_credentials",
    summary="Register automation credentials",
    tags=("automation", "secrets"),
)
def automation_register_credentials(context: ExecutionContext) -> None:
    credentials = context.task.parameters.get("credentials")
    if isinstance(credentials, list):
        _record_state(context, "automation_credentials", credentials)
    context.record(_message(context, "Register automation credentials in Vaultwarden"))


@registry.register(
    "observability.deploy_prometheus",
    summary="Deploy Prometheus monitoring",
    tags=("observability", "monitoring"),
)
def observability_deploy_prometheus(context: ExecutionContext) -> None:
    scrape_targets = context.task.parameters.get("scrape_targets")
    if isinstance(scrape_targets, list):
        _record_state(context, "prometheus_targets", scrape_targets)
    context.record(_message(context, "Deploy Prometheus and scrape configuration"))


@registry.register(
    "observability.deploy_loki",
    summary="Deploy Loki logging",
    tags=("observability", "logging"),
)
def observability_deploy_loki(context: ExecutionContext) -> None:
    context.record(_message(context, "Deploy Loki for log aggregation"))
    _record_state(context, "observability", {"service": "loki", "action": "deploy"})


@registry.register(
    "observability.provision_grafana",
    summary="Provision Grafana dashboards",
    tags=("observability", "dashboards"),
)
def observability_provision_grafana(context: ExecutionContext) -> None:
    dashboards = context.task.parameters.get("dashboards")
    if isinstance(dashboards, list):
        _record_state(context, "grafana_dashboards", dashboards)
    context.record(_message(context, "Provision Grafana dashboards and data sources"))
