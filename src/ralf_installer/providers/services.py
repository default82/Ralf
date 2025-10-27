"""Service provider operations used by the installer."""

from __future__ import annotations

from typing import Iterable, Mapping, Sequence

from .. import explainability


def execute(operation: str, options: dict[str, object], dry_run: bool) -> None:
    operations = {
        "configure_postgresql": _configure_postgresql,
        "configure_gitea": _configure_gitea,
        "configure_vaultwarden": _configure_vaultwarden,
        "configure_prometheus": _configure_prometheus,
        "configure_loki": _configure_loki,
        "configure_grafana": _configure_grafana,
        "configure_vector_db": _configure_vector_db,
        "bootstrap_vector_collections": _bootstrap_vector_collections,
        "register_vector_pipelines": _register_vector_pipelines,
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


def _configure_vector_db(options: Mapping[str, object], *, dry_run: bool) -> None:
    host = _require(options, "host")
    http_port = int(options.get("http_port", 6333))
    grpc_port = int(options.get("grpc_port", 6334))
    admin_secret_raw = options.get("admin_secret")
    snapshot_path_raw = options.get("snapshot_path")

    details = [f"host={host}", f"http_port={http_port}", f"grpc_port={grpc_port}"]
    if admin_secret_raw not in (None, ""):
        details.append(f"admin_secret={admin_secret_raw}")
    if snapshot_path_raw not in (None, ""):
        details.append(f"snapshot_path={snapshot_path_raw}")

    _emit(dry_run, "service", "configure_vector_db", " ".join(details))


def _bootstrap_vector_collections(
    options: Mapping[str, object], *, dry_run: bool
) -> None:
    host = _require(options, "host")
    raw_collections = options.get("collections", [])
    if not isinstance(raw_collections, Iterable) or isinstance(raw_collections, (str, bytes)):
        raise RuntimeError("Vector collections must be defined as an iterable of mappings")

    collections: list[Mapping[str, object]] = []
    for entry in raw_collections:
        if not isinstance(entry, Mapping):
            raise RuntimeError("Each vector collection definition must be a mapping")
        collections.append(entry)

    summary = explainability.build_bootstrap_summary(
        host=str(host),
        http_port=int(options.get("http_port", 6333)),
        grpc_port=int(options.get("grpc_port", 6334)),
        collections=collections,
        admin_secret=str(options.get("admin_secret"))
        if options.get("admin_secret") not in (None, "")
        else None,
        snapshot_path=str(options.get("snapshot_path"))
        if options.get("snapshot_path") not in (None, "")
        else None,
        pipelines=[],
    )

    description = summary.describe()
    _emit(dry_run, "service", "bootstrap_vector_collections", description)


def _register_vector_pipelines(options: Mapping[str, object], *, dry_run: bool) -> None:
    host = _require(options, "host")
    raw_pipelines = options.get("pipelines", [])
    if not isinstance(raw_pipelines, Iterable) or isinstance(raw_pipelines, (str, bytes)):
        raise RuntimeError("Vector pipelines must be defined as an iterable of mappings")

    pipelines: list[Mapping[str, object]] = []
    for entry in raw_pipelines:
        if not isinstance(entry, Mapping):
            raise RuntimeError("Each vector pipeline definition must be a mapping")
        pipelines.append(entry)

    parsed = explainability.parse_pipelines(pipelines)
    description = f"host={host} " + " ".join(pipeline.describe() for pipeline in parsed)
    _emit(dry_run, "service", "register_vector_pipelines", description)


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
