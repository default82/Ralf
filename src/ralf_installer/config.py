"""Configuration utilities for the R.A.L.F. installer."""

from __future__ import annotations

import dataclasses
import pathlib
from typing import Iterable, List, Mapping

import yaml


class ConfigurationError(RuntimeError):
    """Raised when a configuration file is invalid."""


@dataclasses.dataclass(slots=True)
class Action:
    """Describes a provider specific operation for a component."""

    provider: str
    operation: str
    options: Mapping[str, object]


@dataclasses.dataclass(slots=True)
class Component:
    """Represents a deployable component in a profile."""

    name: str
    description: str
    tasks: List[str]
    depends_on: List[str]
    actions: List[Action]

    @classmethod
    def from_mapping(cls, data: Mapping[str, object]) -> "Component":
        try:
            name = str(data["name"])
            description = str(data.get("description", ""))
            raw_tasks = data.get("tasks", [])
            raw_depends = data.get("depends_on", [])
            raw_actions = data.get("actions", [])
        except KeyError as exc:  # pragma: no cover - defensive
            raise ConfigurationError(f"Missing field in component definition: {exc}") from exc

        tasks = _ensure_str_list(raw_tasks, field="tasks", component=name)
        depends_on = _ensure_str_list(raw_depends, field="depends_on", component=name)
        actions = _ensure_action_list(raw_actions, component=name)
        return cls(
            name=name,
            description=description,
            tasks=tasks,
            depends_on=depends_on,
            actions=actions,
        )


@dataclasses.dataclass(slots=True)
class Profile:
    """A collection of components that should be installed together."""

    name: str
    description: str
    components: List[Component]

    @classmethod
    def load(cls, path: pathlib.Path) -> "Profile":
        if not path.exists():
            raise ConfigurationError(f"Profile file does not exist: {path}")

        with path.open("r", encoding="utf-8") as handle:
            payload = yaml.safe_load(handle)

        if not isinstance(payload, Mapping):
            raise ConfigurationError("Profile file must define a mapping at the top level")

        try:
            name = str(payload["name"])
            description = str(payload.get("description", ""))
            components_raw = payload.get("components", [])
        except KeyError as exc:  # pragma: no cover - defensive
            raise ConfigurationError(f"Profile missing required field: {exc}") from exc

        components = [_component_from_obj(obj) for obj in components_raw]
        return cls(name=name, description=description, components=components)

    def resolve_dependencies(self) -> List[Component]:
        """Return components sorted according to their dependencies."""

        by_name = {component.name: component for component in self.components}
        resolved: List[Component] = []
        visiting: set[str] = set()
        visited: set[str] = set()

        def visit(component: Component) -> None:
            if component.name in visited:
                return
            if component.name in visiting:
                raise ConfigurationError(
                    f"Circular dependency detected involving '{component.name}'"
                )
            visiting.add(component.name)
            for dependency in component.depends_on:
                try:
                    dependency_component = by_name[dependency]
                except KeyError as exc:
                    raise ConfigurationError(
                        f"Component '{component.name}' depends on unknown component '{dependency}'"
                    ) from exc
                visit(dependency_component)
            visiting.remove(component.name)
            visited.add(component.name)
            resolved.append(component)

        for component in self.components:
            visit(component)

        return resolved


def _component_from_obj(obj: object) -> Component:
    if not isinstance(obj, Mapping):
        raise ConfigurationError("Each component entry must be a mapping")
    return Component.from_mapping(obj)


def _ensure_str_list(value: object, *, field: str, component: str) -> List[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, Iterable) and not isinstance(value, (bytes, bytearray)):
        result: List[str] = []
        for item in value:
            if not isinstance(item, str):
                raise ConfigurationError(
                    f"Component '{component}' field '{field}' must contain only strings"
                )
            result.append(item)
        return result
    raise ConfigurationError(f"Component '{component}' field '{field}' must be a list of strings")


def _ensure_action_list(value: object, *, component: str) -> List[Action]:
    if value is None:
        return []
    if isinstance(value, Mapping):
        value = [value]
    if isinstance(value, Iterable) and not isinstance(value, (bytes, bytearray, str)):
        result: List[Action] = []
        for index, item in enumerate(value):
            if not isinstance(item, Mapping):
                raise ConfigurationError(
                    "Component '%s' action entry %s must be a mapping" % (component, index)
                )
            provider = item.get("provider")
            operation = item.get("operation")
            options = item.get("options", {})
            if not isinstance(provider, str) or not provider:
                raise ConfigurationError(
                    f"Component '{component}' action {index} is missing a provider"
                )
            if not isinstance(operation, str) or not operation:
                raise ConfigurationError(
                    f"Component '{component}' action {index} is missing an operation"
                )
            if not isinstance(options, Mapping):
                raise ConfigurationError(
                    f"Component '{component}' action {index} options must be a mapping"
                )
            result.append(Action(provider=provider, operation=operation, options=options))
        return result
    raise ConfigurationError(
        f"Component '{component}' field 'actions' must be a mapping or list of mappings"
    )
