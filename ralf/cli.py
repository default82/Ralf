"""Einstiegspunkt für das Ralf-Grundgerüst."""
from __future__ import annotations

import argparse
import logging
from pathlib import Path
from typing import Callable

from .config import RalfConfig
from .logging import configure_logging
from .workflow import BootstrapWorkflow, WorkflowStep


CommandHandler = Callable[[argparse.Namespace, RalfConfig], None]


def _load_steps(config: RalfConfig) -> list[WorkflowStep]:
    """Erzeugt WorkflowStep-Objekte basierend auf der Konfiguration."""
    steps: list[WorkflowStep] = [
        WorkflowStep(identifier=step.name, description=step.description)
        for step in config.bootstrap.steps
    ]
    if not steps:
        # Fallback, falls die Konfiguration noch keine Schritte definiert
        steps = [
            WorkflowStep(
                identifier="initialisation",
                description="Standard-Initialisierung ohne weitere Aktionen",
            )
        ]
    return steps


def handle_bootstrap_command(args: argparse.Namespace, config: RalfConfig) -> None:
    """Führt den Bootstrap-Workflow aus oder zeigt ihn als Trockenlauf an."""
    workflow = BootstrapWorkflow(_load_steps(config))
    if args.dry_run:
        workflow.preview()
    else:
        workflow.run()


def handle_plan_command(args: argparse.Namespace, config: RalfConfig) -> None:  # noqa: ARG001
    """Gibt die konfigurierten Bootstrapschritte auf STDOUT aus."""
    steps = _load_steps(config)
    print("Geplante Bootstrapschritte:")
    for index, step in enumerate(steps, start=1):
        print(f"  {index}. {step.identifier}: {step.description}")


def build_parser() -> argparse.ArgumentParser:
    """Erstellt den Argumentparser für die CLI."""
    parser = argparse.ArgumentParser(
        prog="ralf",
        description="Ralf Automatisierungsgrundgerüst mit Logging",
    )
    parser.add_argument(
        "--config",
        default=Path("config/default.yml"),
        type=Path,
        help="Pfad zur Konfigurationsdatei",
    )
    parser.add_argument(
        "--logging-enabled",
        dest="logging_enabled",
        action=argparse.BooleanOptionalAction,
        help="Logging zur Laufzeit überschreiben",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    bootstrap_parser = subparsers.add_parser(
        "bootstrap",
        help="Führt das definierte Grundgerüst aus",
    )
    bootstrap_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Nur anzeigen, welche Schritte ausgeführt würden",
    )
    bootstrap_parser.set_defaults(handler=handle_bootstrap_command)

    plan_parser = subparsers.add_parser(
        "plan",
        help="Zeigt die konfigurierten Bootstrapschritte",
    )
    plan_parser.set_defaults(handler=handle_plan_command)

    return parser


def main() -> None:
    """Haupteinstiegspunkt für das CLI."""
    parser = build_parser()
    args = parser.parse_args()

    config = RalfConfig.from_file(args.config)

    if args.logging_enabled is not None:
        config.logging.enabled = args.logging_enabled

    configure_logging(config.logging)
    logger = logging.getLogger(__name__)
    logger.info("Ralf CLI gestartet: Befehl=%s", args.command)

    handler: CommandHandler | None = getattr(args, "handler", None)
    if handler is None:
        parser.error("Kein Handler für den gewählten Befehl definiert")
        return

    handler(args, config)


if __name__ == "__main__":
    main()
