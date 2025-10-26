"""Domain models used by the installer."""

from __future__ import annotations

import dataclasses
from typing import Dict, Iterable, List, Mapping

from .errors import ConfigurationError


@dataclasses.dataclass(slots=True)
class TaskSpec:
    """Declarative description of a task that should be executed."""

    identifier: str
    description: str
    parameters: Mapping[str, object]

    def summary(self) -> str:
        return self.description or self.identifier


@dataclasses.dataclass(slots=True)
class Component:
    """Represents a deployable component in a profile."""

    name: str
    description: str
    tasks: List[TaskSpec]
    depends_on: List[str]


@dataclasses.dataclass(slots=True)
class Profile:
    """A collection of components that should be installed together."""

    name: str
    description: str
    components: List[Component]

    def resolve_dependencies(self) -> List[Component]:
        """Return components sorted according to their dependencies."""

        by_name: Dict[str, Component] = {component.name: component for component in self.components}
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


def ensure_str_list(value: object, *, field: str, component: str) -> List[str]:
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
