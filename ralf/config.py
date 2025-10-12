"""Konfigurationsmodelle für das Ralf-Grundgerüst."""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List

import yaml


@dataclass
class LoggingConfig:
    """Konfigurationsparameter für das Logging."""

    enabled: bool = True
    level: str = "INFO"
    log_file: str = "/var/log/ralf/ralf.log"
    max_bytes: int = 5 * 1024 * 1024
    backup_count: int = 5
    release_mode: bool = False


@dataclass
class PathConfig:
    """Standardpfade für Ralf."""

    state_dir: str = "/var/lib/ralf"
    cache_dir: str = "/var/cache/ralf"


@dataclass
class StepDefinition:
    """Beschreibt einen Schritt im Bootstrap-Plan."""

    name: str
    description: str = ""


@dataclass
class BootstrapConfig:
    """Enthält die für den Start vorgesehenen Schritte."""

    steps: List[StepDefinition] = field(default_factory=list)


@dataclass
class RalfConfig:
    """Aggregierte Konfiguration für das Ralf-System."""

    logging: LoggingConfig = field(default_factory=LoggingConfig)
    paths: PathConfig = field(default_factory=PathConfig)
    bootstrap: BootstrapConfig = field(default_factory=BootstrapConfig)

    @classmethod
    def from_file(cls, path: Path) -> "RalfConfig":
        """Lädt die Konfiguration aus einer YAML-Datei."""
        with path.open("r", encoding="utf-8") as handle:
            data: Dict[str, Any] = yaml.safe_load(handle) or {}

        logging_cfg = LoggingConfig(**data.get("logging", {}))
        paths_cfg = PathConfig(**data.get("paths", {}))

        bootstrap_data = data.get("bootstrap", {})
        steps_raw = bootstrap_data.get("steps", [])
        steps: List[StepDefinition] = []
        for entry in steps_raw:
            if isinstance(entry, dict):
                steps.append(StepDefinition(**entry))

        bootstrap_cfg = BootstrapConfig(steps=steps)

        return cls(logging=logging_cfg, paths=paths_cfg, bootstrap=bootstrap_cfg)


__all__ = [
    "BootstrapConfig",
    "LoggingConfig",
    "PathConfig",
    "RalfConfig",
    "StepDefinition",
]
