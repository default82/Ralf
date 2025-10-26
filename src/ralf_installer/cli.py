"""Command line interface for the R.A.L.F. installer."""

from __future__ import annotations

import argparse
import json
import pathlib
from typing import Optional

from .config import ConfigurationError, load_profile
from .execution.report import ComponentResult, ExecutionReport, TaskResult
from .installer import Installer


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="R.A.L.F. installer")
    parser.add_argument(
        "profile",
        help="Path to the installer profile (YAML)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Plan the installation but do not execute any tasks",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the execution report as JSON",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    profile_path = pathlib.Path(args.profile)

    try:
        profile = load_profile(profile_path)
    except ConfigurationError as exc:
        parser.error(str(exc))
        return 2

    installer = Installer(profile, dry_run=args.dry_run)
    report = installer.execute()

    if args.json:
        _print_json(report)
    else:
        _print_human(report, profile.description)

    return 0


def _print_json(report: ExecutionReport) -> None:
    print(json.dumps(report.as_dict(), indent=2))


def _print_human(report: ExecutionReport, profile_description: str) -> None:
    print(f"Profile: {report.profile_name}")
    mode = "DRY-RUN" if report.dry_run else "APPLY"
    print(f"Mode: {mode}")
    if profile_description:
        print()
        print(profile_description)
    print()

    for component in report.components:
        _print_component(component)
        print()

    planned = set(report.planned_components)
    processed = {component.name for component in report.components}
    pending = planned - processed
    if pending:
        print("Pending components:")
        for name in pending:
            print(f"  - {name}")


def _print_component(component: ComponentResult) -> None:
    status_symbol = {
        "executed": "✓",
        "skipped": "⊘",
        "failed": "✗",
    }.get(component.status, "?")
    print(f"{status_symbol} {component.name} [{component.status}]")
    if component.description:
        print(f"  {component.description}")
    for task in component.tasks:
        _print_task(task)
    if component.messages:
        print("  Notes:")
        for message in component.messages:
            print(f"    - {message}")


def _print_task(task: TaskResult) -> None:
    status_symbol = {
        "executed": "  ▸",
        "skipped": "  ▹",
        "failed": "  ✗",
    }.get(task.status, "  ?")
    print(f"{status_symbol} {task.identifier}")
    if task.description and task.description != task.identifier:
        print(f"    {task.description}")
    if task.messages:
        for message in task.messages:
            print(f"    - {message}")


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(main())
