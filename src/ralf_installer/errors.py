"""Custom exceptions for the R.A.L.F. installer."""

from __future__ import annotations


class ConfigurationError(RuntimeError):
    """Raised when configuration files or payloads are invalid."""


class RegistryError(RuntimeError):
    """Raised when the task registry encounters an invalid operation."""


class TaskExecutionError(RuntimeError):
    """Raised when a task fails while the installer is running."""
