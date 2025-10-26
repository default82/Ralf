"""Reporting structures for installer runs."""

from __future__ import annotations

import dataclasses
from typing import List


@dataclasses.dataclass(slots=True)
class TaskResult:
    identifier: str
    description: str
    status: str
    messages: List[str]


@dataclasses.dataclass(slots=True)
class ComponentResult:
    name: str
    description: str
    status: str
    tasks: List[TaskResult]
    messages: List[str]


@dataclasses.dataclass(slots=True)
class ExecutionReport:
    profile_name: str
    dry_run: bool
    planned_components: List[str]
    components: List[ComponentResult]

    @property
    def executed_components(self) -> List[str]:
        return [component.name for component in self.components if component.status == "executed"]

    @property
    def skipped_components(self) -> List[str]:
        return [component.name for component in self.components if component.status == "skipped"]

    def as_dict(self) -> dict:
        return {
            "profile_name": self.profile_name,
            "dry_run": self.dry_run,
            "planned_components": self.planned_components,
            "components": [
                {
                    "name": component.name,
                    "description": component.description,
                    "status": component.status,
                    "messages": component.messages,
                    "tasks": [
                        {
                            "identifier": task.identifier,
                            "description": task.description,
                            "status": task.status,
                            "messages": task.messages,
                        }
                        for task in component.tasks
                    ],
                }
                for component in self.components
            ],
        }
