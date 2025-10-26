"""Provider registry for installer actions."""

from __future__ import annotations

from typing import Callable, Dict

from ..config import Action
from . import proxmox, services


Handler = Callable[[str, dict[str, object], bool], None]

_PROVIDERS: Dict[str, Handler] = {
    "proxmox": proxmox.execute,
    "service": services.execute,
}


def execute_action(action: Action, *, dry_run: bool) -> None:
    """Dispatch an action to the responsible provider handler."""

    try:
        handler = _PROVIDERS[action.provider]
    except KeyError as exc:  # pragma: no cover - defensive
        raise RuntimeError(
            f"Unknown provider '{action.provider}' for component action '{action.operation}'"
        ) from exc

    handler(action.operation, dict(action.options), dry_run)


__all__ = ["execute_action"]
