"""Command line interface for the R.A.L.F. installer."""

from __future__ import annotations

import argparse
import json
import pathlib
from typing import Optional

from .config import ConfigurationError, Profile
from .installer import ExecutionReport, Installer


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
        profile = Profile.load(profile_path)
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
    if profile_description:
        print(profile_description)
        print()

    if report.skipped_components:
        print("Planned components (dry-run):")
        for name in report.skipped_components:
            print(f"  - {name}")
    else:
        print("Executed components:")
        for name in report.executed_components:
            print(f"  - {name}")

    pending = [name for name in report.planned_components if name not in report.executed_components]
    if pending and not report.skipped_components:
        print("\nPending components:")
        for name in pending:
            print(f"  - {name}")


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(main())
