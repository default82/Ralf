"""Configuration utilities for the R.A.L.F. installer."""

from __future__ import annotations

import dataclasses
import pathlib
from typing import Iterable, List, Mapping, Optional

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
    workflows: List["WorkflowTemplate"] = dataclasses.field(default_factory=list)
    scheduler: Optional["Scheduler"] = None

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
            workflows_raw = payload.get("workflows", [])
            scheduler_raw = payload.get("scheduler")
        except KeyError as exc:  # pragma: no cover - defensive
            raise ConfigurationError(f"Profile missing required field: {exc}") from exc

        components = [_component_from_obj(obj) for obj in components_raw]
        workflows = [_workflow_from_obj(obj) for obj in workflows_raw]
        scheduler = Scheduler.from_mapping(scheduler_raw) if scheduler_raw else None
        return cls(
            name=name,
            description=description,
            components=components,
            workflows=workflows,
            scheduler=scheduler,
        )

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


@dataclasses.dataclass(slots=True)
class WorkflowTemplate:
    """Declarative description of a workflow implementation for a loop."""

    name: str
    loop: str
    runtime: str
    entrypoint: str
    description: str
    inputs: List[str]
    outputs: List[str]

    @classmethod
    def from_mapping(cls, data: Mapping[str, object]) -> "WorkflowTemplate":
        try:
            name = str(data["name"])
            loop = str(data["loop"])
            runtime = str(data["runtime"])
        except KeyError as exc:  # pragma: no cover - defensive
            raise ConfigurationError(f"Workflow definition is missing required field: {exc}") from exc

        entrypoint_raw = data.get("entrypoint", name)
        description_raw = data.get("description", "")
        inputs_raw = data.get("inputs", [])
        outputs_raw = data.get("outputs", [])

        entrypoint = str(entrypoint_raw)
        description = str(description_raw)
        inputs = _ensure_str_list(inputs_raw, field="inputs", component=name)
        outputs = _ensure_str_list(outputs_raw, field="outputs", component=name)

        return cls(
            name=name,
            loop=loop,
            runtime=runtime.lower(),
            entrypoint=entrypoint,
            description=description,
            inputs=inputs,
            outputs=outputs,
        )


def _workflow_from_obj(obj: object) -> WorkflowTemplate:
    if not isinstance(obj, Mapping):
        raise ConfigurationError("Each workflow entry must be a mapping")
    return WorkflowTemplate.from_mapping(obj)


@dataclasses.dataclass(slots=True)
class IntervalTrigger:
    """Describes a cron or timer based trigger for a loop."""

    kind: str
    expression: Optional[str] = None
    interval: Optional[str] = None
    timezone: Optional[str] = None

    @classmethod
    def from_mapping(cls, data: Mapping[str, object], *, loop: str, index: int) -> "IntervalTrigger":
        kind_raw = data.get("type")
        if not isinstance(kind_raw, str) or not kind_raw.strip():
            raise ConfigurationError(
                f"Scheduler for loop '{loop}' trigger {index} must define a non-empty 'type'"
            )

        kind = kind_raw.lower()
        timezone_raw = data.get("timezone")
        timezone = str(timezone_raw) if isinstance(timezone_raw, str) and timezone_raw else None

        if kind == "cron":
            expression = data.get("expression")
            if not isinstance(expression, str) or not expression.strip():
                raise ConfigurationError(
                    f"Scheduler for loop '{loop}' trigger {index} must define a cron 'expression'"
                )
            return cls(kind="cron", expression=expression.strip(), timezone=timezone)

        if kind == "timer":
            interval_raw = data.get("every")
            if interval_raw is None:
                interval_raw = data.get("interval")
            if isinstance(interval_raw, (int, float)):
                interval = str(interval_raw)
            elif isinstance(interval_raw, str) and interval_raw.strip():
                interval = interval_raw.strip()
            else:
                raise ConfigurationError(
                    f"Scheduler for loop '{loop}' trigger {index} must define an interval via 'every' or 'interval'"
                )
            return cls(kind="timer", interval=interval, timezone=timezone)

        raise ConfigurationError(
            f"Scheduler for loop '{loop}' trigger {index} has unsupported type '{kind_raw}'"
        )

    def describe(self) -> str:
        """Return a human readable representation of the trigger."""

        if self.kind == "cron" and self.expression:
            base = f"cron '{self.expression}'"
        elif self.kind == "timer" and self.interval:
            base = f"timer every {self.interval}"
        else:  # pragma: no cover - defensive
            base = self.kind
        if self.timezone:
            return f"{base} ({self.timezone})"
        return base


@dataclasses.dataclass(slots=True)
class LoopSchedule:
    """Holds triggers for a specific loop."""

    loop: str
    description: str
    triggers: List[IntervalTrigger]

    @classmethod
    def from_mapping(cls, loop: str, data: Mapping[str, object]) -> "LoopSchedule":
        if not isinstance(data, Mapping):
            raise ConfigurationError(f"Scheduler loop '{loop}' must be defined as a mapping")

        description_raw = data.get("description", "")
        triggers_raw = data.get("triggers", [])
        description = str(description_raw)
        if isinstance(triggers_raw, Mapping):
            triggers_raw = [triggers_raw]
        if not isinstance(triggers_raw, Iterable) or isinstance(triggers_raw, (bytes, bytearray, str)):
            raise ConfigurationError(
                f"Scheduler loop '{loop}' must define 'triggers' as a list of mappings"
            )

        triggers: List[IntervalTrigger] = []
        for index, item in enumerate(triggers_raw):
            if not isinstance(item, Mapping):
                raise ConfigurationError(
                    f"Scheduler loop '{loop}' trigger {index} must be a mapping"
                )
            triggers.append(IntervalTrigger.from_mapping(item, loop=loop, index=index))

        return cls(loop=loop, description=description, triggers=triggers)


@dataclasses.dataclass(slots=True)
class Scheduler:
    """Scheduler configuration for loop triggers."""

    loops: Mapping[str, LoopSchedule]

    @classmethod
    def from_mapping(cls, data: Mapping[str, object]) -> "Scheduler":
        if not isinstance(data, Mapping):
            raise ConfigurationError("Scheduler configuration must be a mapping")

        loops_raw = data.get("loops", {})
        if not isinstance(loops_raw, Mapping):
            raise ConfigurationError("Scheduler 'loops' must be a mapping of loop names")

        loops: dict[str, LoopSchedule] = {}
        for loop_name, loop_data in loops_raw.items():
            loops[str(loop_name)] = LoopSchedule.from_mapping(str(loop_name), loop_data)

        return cls(loops=loops)

    def get_loop(self, loop: str) -> Optional[LoopSchedule]:
        """Return the schedule for a loop if configured."""

        return self.loops.get(loop)


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
