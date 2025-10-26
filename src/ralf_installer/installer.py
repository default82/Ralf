"""Core installer routines."""

from __future__ import annotations

from typing import Any, Dict, List

from .errors import RegistryError, TaskExecutionError
from .execution.context import ExecutionContext
from .execution.report import ComponentResult, ExecutionReport, TaskResult
from .models import Component, Profile
from .tasks import registry


class Installer:
    """High level coordinator that turns profiles into actionable steps."""

    def __init__(self, profile: Profile, *, dry_run: bool = False) -> None:
        self._profile = profile
        self._dry_run = dry_run
        self._shared_state: Dict[str, Any] = {}

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
        """Execute the installer for the configured profile."""

        ordered_components = self.plan()
        planned_names = [component.name for component in ordered_components]
        component_results: List[ComponentResult] = []

        for component in ordered_components:
            component_messages: List[str] = []
            task_results: List[TaskResult] = []

            if self._dry_run:
                for task in component.tasks:
                    message = f"DRY-RUN: would execute task '{task.identifier}'"
                    task_results.append(
                        TaskResult(
                            identifier=task.identifier,
                            description=task.summary(),
                            status="skipped",
                            messages=[message],
                        )
                    )
                    component_messages.append(message)
                component_results.append(
                    ComponentResult(
                        name=component.name,
                        description=component.description,
                        status="skipped",
                        tasks=task_results,
                        messages=component_messages,
                    )
                )
                continue

            component_failed = False
            for task in component.tasks:
                task_events: List[str] = []
                context = ExecutionContext(
                    profile=self._profile,
                    component=component,
                    task=task,
                    dry_run=self._dry_run,
                    shared_state=self._shared_state,
                    events=task_events,
                )

                try:
                    definition = registry.get(task.identifier)
                except RegistryError as exc:
                    failure_message = str(exc)
                    task_events.append(failure_message)
                    task_results.append(
                        TaskResult(
                            identifier=task.identifier,
                            description=task.summary(),
                            status="failed",
                            messages=list(task_events),
                        )
                    )
                    component_messages.extend(task_events)
                    component_failed = True
                    break

                try:
                    definition.run(context)
                    if not task_events:
                        context.record(task.summary())
                    task_results.append(
                        TaskResult(
                            identifier=task.identifier,
                            description=task.summary(),
                            status="executed",
                            messages=list(task_events),
                        )
                    )
                    component_messages.extend(task_events)
                except TaskExecutionError as exc:
                    context.record(str(exc))
                    task_results.append(
                        TaskResult(
                            identifier=task.identifier,
                            description=task.summary(),
                            status="failed",
                            messages=list(task_events),
                        )
                    )
                    component_messages.extend(task_events)
                    component_failed = True
                    break

            status = "failed" if component_failed else "executed"
            component_results.append(
                ComponentResult(
                    name=component.name,
                    description=component.description,
                    status=status,
                    tasks=task_results,
                    messages=component_messages,
                )
            )

            if component_failed:
                break

        return ExecutionReport(
            profile_name=self._profile.name,
            dry_run=self._dry_run,
            planned_components=planned_names,
            components=component_results,
        )
