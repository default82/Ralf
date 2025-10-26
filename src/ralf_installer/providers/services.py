"""High level service configuration helpers."""

from __future__ import annotations

from typing import Mapping


def execute(operation: str, options: dict[str, object], dry_run: bool) -> None:
    operations = {
        "configure_postgresql": _configure_postgresql,
        "configure_gitea": _configure_gitea,
        "configure_vaultwarden": _configure_vaultwarden,
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


def _require(options: Mapping[str, object], key: str) -> object:
    try:
        value = options[key]
    except KeyError as exc:  # pragma: no cover - defensive
        raise RuntimeError(f"Missing required option '{key}'") from exc
    if value in (None, ""):
        raise RuntimeError(f"Option '{key}' must not be empty")
    return value


def _emit(dry_run: bool, provider: str, operation: str, description: str) -> None:
    prefix = "DRY-RUN" if dry_run else "EXEC"
    print(f"[{prefix}] {provider}:{operation} {description}")
