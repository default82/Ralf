"""Task registry used by the installer runtime."""

from __future__ import annotations

import dataclasses
from typing import Callable, Dict, Iterable, Tuple

from ..errors import RegistryError, TaskExecutionError
from ..execution.context import ExecutionContext

TaskHandler = Callable[[ExecutionContext], None]


@dataclasses.dataclass(slots=True)
class TaskDefinition:
    identifier: str
    summary: str
    handler: TaskHandler
    tags: Tuple[str, ...]

    def run(self, context: ExecutionContext) -> None:
        try:
            self.handler(context)
        except TaskExecutionError:
            raise
        except Exception as exc:  # pragma: no cover - defensive
            raise TaskExecutionError(
                f"Task '{self.identifier}' failed: {exc}"
            ) from exc


class TaskRegistry:
    """Book-keeping for available task handlers."""

    def __init__(self) -> None:
        self._tasks: Dict[str, TaskDefinition] = {}

    def register(self, identifier: str, *, summary: str, tags: Iterable[str] | None = None) -> Callable[[TaskHandler], TaskHandler]:
        tags_tuple = tuple(tags or ())

        def decorator(func: TaskHandler) -> TaskHandler:
            if identifier in self._tasks:
                raise RegistryError(f"Task '{identifier}' is already registered")
            self._tasks[identifier] = TaskDefinition(
                identifier=identifier,
                summary=summary,
                handler=func,
                tags=tags_tuple,
            )
            return func

        return decorator

    def get(self, identifier: str) -> TaskDefinition:
        try:
            return self._tasks[identifier]
        except KeyError as exc:
            raise RegistryError(f"Unknown task identifier: {identifier}") from exc

    def __contains__(self, identifier: str) -> bool:
        return identifier in self._tasks

    def __iter__(self):  # pragma: no cover - simple delegation
        return iter(self._tasks.values())


registry = TaskRegistry()

__all__ = ["registry", "TaskDefinition", "TaskRegistry", "TaskHandler"]
