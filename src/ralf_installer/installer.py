"""Core installer routines."""

from __future__ import annotations

import dataclasses
from typing import Iterable, List

from .config import Component, Profile


@dataclasses.dataclass(slots=True)
class ExecutionReport:
    """Represents the result of an installer run."""

    planned_components: List[str]
    executed_components: List[str]
    skipped_components: List[str]

    def as_dict(self) -> dict[str, List[str]]:
        return {
            "planned_components": self.planned_components,
            "executed_components": self.executed_components,
            "skipped_components": self.skipped_components,
        }


class Installer:
    """High level coordinator that turns profiles into actionable steps."""

    def __init__(self, profile: Profile, *, dry_run: bool = False) -> None:
        self._profile = profile
        self._dry_run = dry_run

    @property
    def profile(self) -> Profile:
        return self._profile

    @property
    def dry_run(self) -> bool:
        return self._dry_run

    def plan(self) -> List[Component]:
        """Return components in the order they will be processed."""
        return self._profile.resolve_dependencies()

    def execute(self) -> ExecutionReport:
        """Simulate executing the installer."""
        ordered_components = self.plan()
        executed: List[str] = []
        skipped: List[str] = []

        for component in ordered_components:
            if self._dry_run:
                skipped.append(component.name)
            else:
                _run_component(component)
                executed.append(component.name)

        return ExecutionReport(
            planned_components=[component.name for component in ordered_components],
            executed_components=executed,
            skipped_components=skipped,
        )


def _run_component(component: Component) -> None:
    """Placeholder for the real installer logic."""

    for task in component.tasks:
        _log_task(component.name, task)


def _log_task(component_name: str, task: str) -> None:
    print(f"[{component_name}] {task}")
