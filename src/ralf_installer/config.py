"""Configuration utilities for the R.A.L.F. installer."""

from __future__ import annotations

import pathlib
from typing import Any, Mapping

import yaml

from .errors import ConfigurationError
from .models import Component, Profile, TaskSpec, ensure_str_list


def load_profile(path: pathlib.Path) -> Profile:
    """Load a profile definition from a YAML file."""

    if not path.exists():
        raise ConfigurationError(f"Profile file does not exist: {path}")

    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)

    if not isinstance(payload, Mapping):
        raise ConfigurationError("Profile file must define a mapping at the top level")

    try:
        name = str(payload["name"])
    except KeyError as exc:  # pragma: no cover - defensive
        raise ConfigurationError("Profile missing required field: 'name'") from exc

    description = str(payload.get("description", ""))
    components_raw = payload.get("components", [])

    components = [_component_from_obj(obj) for obj in components_raw]
    return Profile(name=name, description=description, components=components)


def _component_from_obj(obj: object) -> Component:
    if not isinstance(obj, Mapping):
        raise ConfigurationError("Each component entry must be a mapping")

    try:
        name = str(obj["name"])
    except KeyError as exc:  # pragma: no cover - defensive
        raise ConfigurationError("Component missing required field: 'name'") from exc

    description = str(obj.get("description", ""))
    tasks_raw = obj.get("tasks", [])
    depends_raw = obj.get("depends_on", [])

    tasks = [_task_from_obj(task, component=name) for task in tasks_raw]
    depends_on = ensure_str_list(depends_raw, field="depends_on", component=name)

    return Component(name=name, description=description, tasks=tasks, depends_on=depends_on)


def _task_from_obj(obj: object, *, component: str) -> TaskSpec:
    if isinstance(obj, str):
        identifier = obj.strip()
        if not identifier:
            raise ConfigurationError(
                f"Component '{component}' contains an empty task definition"
            )
        return TaskSpec(identifier=identifier, description=identifier, parameters={})

    if isinstance(obj, Mapping):
        identifier = _coerce_task_identifier(obj, component=component)
        description = str(obj.get("description", ""))
        parameters_obj = obj.get("parameters", {})

        if parameters_obj is None:
            parameters_obj = {}
        if not isinstance(parameters_obj, Mapping):
            raise ConfigurationError(
                f"Component '{component}' task '{identifier}' parameters must be a mapping"
            )

        parameters: dict[str, Any] = {str(key): value for key, value in parameters_obj.items()}
        return TaskSpec(identifier=identifier, description=description, parameters=parameters)

    raise ConfigurationError(
        f"Component '{component}' contains a task definition of unsupported type: {type(obj)!r}"
    )


def _coerce_task_identifier(data: Mapping[str, object], *, component: str) -> str:
    for key in ("id", "identifier", "task", "name"):
        if key in data:
            identifier = str(data[key])
            if identifier:
                return identifier
    raise ConfigurationError(
        f"Component '{component}' task definition missing identifier (one of id/identifier/task/name)"
    )


__all__ = ["load_profile", "ConfigurationError"]
