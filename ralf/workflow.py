"""Einfache Workflow-Helfer für den ersten Prototyp."""
from __future__ import annotations

from dataclasses import dataclass
import logging
from typing import Iterable, List


@dataclass
class WorkflowStep:
    """Beschreibt einen einzelnen Schritt im Provisioning-Workflow."""

    identifier: str
    description: str


class BootstrapWorkflow:
    """Führt das Grundgerüst Schritt für Schritt aus."""

    def __init__(self, steps: Iterable[WorkflowStep]) -> None:
        self._steps: List[WorkflowStep] = list(steps)
        self._logger = logging.getLogger(self.__class__.__name__)

    def preview(self) -> None:
        """Zeigt die geplanten Schritte ohne Ausführung."""
        if not self._steps:
            self._logger.warning("Keine Bootstrapschritte definiert")
            return
        self._logger.info("Trockenlauf: %d Schritte", len(self._steps))
        for step in self._steps:
            self._logger.info("[PREVIEW] %s — %s", step.identifier, step.description)

    def run(self) -> None:
        """Führt die konfigurierten Schritte aus.

        Aktuell werden die Schritte nur protokolliert, die konkrete Umsetzung
        folgt in späteren Iterationen. Die detaillierten Logs dienen zur
        Fehlersuche und lassen sich in Release-Builds deaktivieren.
        """

        if not self._steps:
            self._logger.warning("Keine Bootstrapschritte definiert")
            return

        self._logger.info("Starte Bootstrap-Workflow (%d Schritte)", len(self._steps))
        for step in self._steps:
            self._logger.info("[%s] gestartet — %s", step.identifier, step.description)
            self._logger.debug("[%s] simulierte Ausführung", step.identifier)
        self._logger.info("Bootstrap-Workflow abgeschlossen")


__all__ = ["BootstrapWorkflow", "WorkflowStep"]
