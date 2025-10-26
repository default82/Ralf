"""Execution context objects passed to tasks."""

from __future__ import annotations

import dataclasses
from typing import Any, Dict, List

from ..models import Component, Profile, TaskSpec


@dataclasses.dataclass(slots=True)
class ExecutionContext:
    """Runtime information handed to task handlers."""

    profile: Profile
    component: Component
    task: TaskSpec
    dry_run: bool
    shared_state: Dict[str, Any]
    events: List[str]

    def record(self, message: str) -> None:
        entry = f"[{self.component.name}:{self.task.identifier}] {message}"
        self.events.append(entry)

