"""Service provider operations used by the installer."""

from __future__ import annotations

from typing import Iterable, Mapping, Sequence


def execute(operation: str, options: dict[str, object], dry_run: bool) -> None:
    operations = {
        "configure_postgresql": _configure_postgresql,
        "configure_gitea": _configure_gitea,
        "configure_vaultwarden": _configure_vaultwarden,
        "configure_prometheus": _configure_prometheus,
        "configure_loki": _configure_loki,
        "configure_grafana": _configure_grafana,
        "register_prometheus_targets": _register_prometheus_targets,
    }

    try:
        handler = operations[operation]
    except KeyError as exc:  # pragma: no cover - defensive
        raise RuntimeError(f"Unsupported service operation '{operation}'") from exc

    handler(options, dry_run=dry_run)


def _configure_postgresql(options: Mapping[str, object], *, dry_run: bool) -> None:
    host = _require(options, "host")
    port = options.get("port", 5432)
    admin_user = options.get("admin_user", "postgres")
    database = _require(options, "database")
    app_user_secret = _require(options, "app_user_secret")

    _emit(
        dry_run,
        "service",
        "configure_postgresql",
        f"host={host}:{port} admin_user={admin_user} database={database} app_secret={app_user_secret}",
    )


def _configure_gitea(options: Mapping[str, object], *, dry_run: bool) -> None:
    url = _require(options, "url")
    database_dsn = _require(options, "database_dsn")
    admin_secret = _require(options, "admin_secret")
    oauth_secret = options.get("oauth_secret")

    description = f"url={url} db={database_dsn} admin_secret={admin_secret}"
    if oauth_secret:
        description += f" oauth_secret={oauth_secret}"
    _emit(dry_run, "service", "configure_gitea", description)


def _configure_vaultwarden(options: Mapping[str, object], *, dry_run: bool) -> None:
    url = _require(options, "url")
    admin_token_secret = _require(options, "admin_token_secret")
    smtp_secret = options.get("smtp_secret")

    description = f"url={url} admin_token_secret={admin_token_secret}"
    if smtp_secret:
        description += f" smtp_secret={smtp_secret}"
    _emit(dry_run, "service", "configure_vaultwarden", description)


def _configure_prometheus(options: Mapping[str, object], *, dry_run: bool) -> None:
    host = _require(options, "host")
    config_path = _require(options, "config_path")
    rules = _as_list(options.get("rules", []))

    description = f"host={host} config={config_path}"
    if rules:
        description += " rules=" + ",".join(map(str, rules))
    _emit(dry_run, "service", "configure_prometheus", description)


def _configure_loki(options: Mapping[str, object], *, dry_run: bool) -> None:
    host = _require(options, "host")
    config_path = _require(options, "config_path")
    retention = options.get("retention", "7d")

    description = (
        f"host={host} config={config_path} retention={retention}"
    )
    _emit(dry_run, "service", "configure_loki", description)


def _configure_grafana(options: Mapping[str, object], *, dry_run: bool) -> None:
    host = _require(options, "host")
    admin_secret = _require(options, "admin_secret")
    datasources = _as_list(options.get("datasources", []))
    dashboards = _as_list(options.get("dashboards", []))

    description = f"host={host} admin_secret={admin_secret}"
    if datasources:
        description += " datasources=" + ",".join(map(str, datasources))
    if dashboards:
        description += " dashboards=" + ",".join(map(str, dashboards))
    _emit(dry_run, "service", "configure_grafana", description)


def _register_prometheus_targets(
    options: Mapping[str, object], *, dry_run: bool
) -> None:
    host = _require(options, "host")
    target_file = _require(options, "target_file")
    services = options.get("services", [])

    if not isinstance(services, Iterable) or isinstance(services, (str, bytes)):
        raise RuntimeError("'services' must be an iterable of mappings")

    rendered: list[str] = []
    for entry in services:
        if not isinstance(entry, Mapping):
            raise RuntimeError("Each service definition must be a mapping")
        name = _require(entry, "name")
        targets = entry.get("targets", [])
        if not isinstance(targets, Sequence) or isinstance(targets, (str, bytes)):
            raise RuntimeError("Service targets must be a sequence of strings")
        if not targets:
            raise RuntimeError("Service targets must not be empty")
        rendered.append(f"{name}={','.join(map(str, targets))}")

    description = (
        f"host={host} target_file={target_file} services=" + ";".join(rendered)
        if rendered
        else f"host={host} target_file={target_file}"
    )
    _emit(dry_run, "service", "register_prometheus_targets", description)


def _require(options: Mapping[str, object], key: str) -> object:
    try:
        value = options[key]
    except KeyError as exc:  # pragma: no cover - defensive
        raise RuntimeError(f"Missing required option '{key}'") from exc
    if value in (None, ""):
        raise RuntimeError(f"Option '{key}' must not be empty")
    return value


def _as_list(value: object) -> list[str]:
    if value in (None, ""):
        return []
    if isinstance(value, (str, bytes)):
        return [str(value)]
    if not isinstance(value, Iterable):
        raise RuntimeError("Value must be iterable to coerce into a list")
    return [str(item) for item in value]


def _emit(dry_run: bool, provider: str, operation: str, description: str) -> None:
    prefix = "DRY-RUN" if dry_run else "EXEC"
    print(f"[{prefix}] {provider}:{operation} {description}")
