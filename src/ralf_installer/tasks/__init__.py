"""Task package for the R.A.L.F. installer."""

from .registry import registry, TaskDefinition, TaskHandler, TaskRegistry

# Import the catalog to ensure built-in tasks are registered on package import.
from . import catalog as _catalog  # noqa: F401  (imported for side effects)

__all__ = ["registry", "TaskDefinition", "TaskHandler", "TaskRegistry"]
