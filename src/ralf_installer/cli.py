"""Command line interface for the R.A.L.F. installer."""

from __future__ import annotations

import argparse
import dataclasses
import json
import pathlib
import sys
from typing import Iterable, List, Optional

from .config import ConfigurationError, Profile
from .installer import ExecutionReport, Installer


def build_parser() -> argparse.ArgumentParser:
    """Return the parser for the legacy install command."""

    return _build_install_parser()


def _build_install_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="R.A.L.F. installer")
    parser.add_argument("profile", help="Path to the installer profile (YAML)")
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


def _build_workflow_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Activate workflows defined in a profile")
    parser.add_argument("profile", help="Path to the installer profile (YAML)")
    parser.add_argument(
        "--runtime",
        choices=("n8n", "foreman", "all"),
        default="all",
        help="Limit activation to a specific runtime",
    )
    parser.add_argument(
        "--loop",
        action="append",
        dest="loops",
        help="Only activate workflows for the given loop (can be used multiple times)",
    )
    return parser


def _build_report_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Aggregate policy pipeline results")
    parser.add_argument("profile", help="Path to the installer profile (YAML)")
    parser.add_argument(
        "--results-dir",
        help="Directory containing JSON policy result files (defaults to <profile>/policy_results)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the aggregated report as JSON",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    if argv and argv[0] == "enable-workflows":
        return _handle_enable_workflows(argv[1:])
    if argv and argv[0] == "report":
        return _handle_policy_report(argv[1:])

    parser = _build_install_parser()
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


def _handle_enable_workflows(argv: Iterable[str]) -> int:
    parser = _build_workflow_parser()
    args = parser.parse_args(list(argv))

    profile_path = pathlib.Path(args.profile)
    try:
        profile = Profile.load(profile_path)
    except ConfigurationError as exc:
        parser.error(str(exc))
        return 2

    workflows = profile.workflows
    if args.runtime != "all":
        workflows = [wf for wf in workflows if wf.runtime == args.runtime]

    if args.loops:
        selected_loops = {loop.lower() for loop in args.loops}
        workflows = [wf for wf in workflows if wf.loop.lower() in selected_loops]

    if not workflows:
        print("No workflows matched the requested filters.")
        return 0

    for workflow in workflows:
        print(f"Activating {workflow.runtime} workflow '{workflow.name}' for loop '{workflow.loop}'")
        print(f"  entrypoint: {workflow.entrypoint}")
        if workflow.description:
            print(f"  description: {workflow.description}")
        if workflow.phases:
            print("  phases:")
            for phase in workflow.phases:
                print(f"    - {phase}")
        if workflow.inputs:
            print("  inputs:")
            for item in workflow.inputs:
                print(f"    - {item}")
        if workflow.outputs:
            print("  outputs:")
            for item in workflow.outputs:
                print(f"    - {item}")

        if profile.scheduler:
            schedule = profile.scheduler.get_loop(workflow.loop)
            if schedule and schedule.triggers:
                print("  triggers:")
                for trigger in schedule.triggers:
                    print(f"    - {trigger.describe()}")

    return 0


def _handle_policy_report(argv: Iterable[str]) -> int:
    parser = _build_report_parser()
    args = parser.parse_args(list(argv))

    profile_path = pathlib.Path(args.profile)
    try:
        profile = Profile.load(profile_path)
    except ConfigurationError as exc:
        parser.error(str(exc))
        return 2

    results_dir = pathlib.Path(args.results_dir) if args.results_dir else profile_path.parent / "policy_results"
    try:
        results = _collect_policy_results(results_dir)
    except OSError as exc:
        parser.error(f"Failed to read policy results: {exc}")
        return 2
    except ValueError as exc:
        parser.error(str(exc))
        return 2

    summary = PolicyReportSummary(
        profile_name=profile.name,
        profile_description=profile.description,
        results=results,
    )

    if args.json:
        print(json.dumps(summary.as_dict(), indent=2))
    else:
        _print_policy_summary(summary)

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


@dataclasses.dataclass(slots=True)
class PolicyResult:
    policy: str
    status: str
    severity: Optional[str]
    target: Optional[str]
    details: Optional[str]
    source: str

    def as_dict(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "policy": self.policy,
            "status": self.status,
            "source": self.source,
        }
        if self.severity:
            payload["severity"] = self.severity
        if self.target:
            payload["target"] = self.target
        if self.details:
            payload["details"] = self.details
        return payload


@dataclasses.dataclass(slots=True)
class PolicyReportSummary:
    profile_name: str
    profile_description: str
    results: List[PolicyResult]

    def as_dict(self) -> dict[str, object]:
        return {
            "profile": self.profile_name,
            "description": self.profile_description,
            "results": [result.as_dict() for result in self.results],
        }


def _collect_policy_results(results_dir: pathlib.Path) -> List[PolicyResult]:
    if not results_dir.exists():
        return []
    if not results_dir.is_dir():
        raise ValueError(f"Policy results path '{results_dir}' is not a directory")

    collected: List[PolicyResult] = []
    for path in sorted(results_dir.glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON in policy result '{path}': {exc}") from exc

        if not isinstance(payload, dict):
            raise ValueError(f"Policy result '{path}' must contain a JSON object")

        policy = str(payload.get("policy") or path.stem)
        status = str(payload.get("status", "unknown")).upper()
        severity = payload.get("severity")
        target = payload.get("target")
        details = payload.get("details") or payload.get("summary")

        collected.append(
            PolicyResult(
                policy=policy,
                status=status,
                severity=str(severity) if severity is not None else None,
                target=str(target) if target is not None else None,
                details=str(details) if details is not None else None,
                source=str(path),
            )
        )

    return collected


def _print_policy_summary(summary: PolicyReportSummary) -> None:
    header = f"Policy pipeline report for profile '{summary.profile_name}'"
    print(header)
    print("=" * len(header))

    if summary.profile_description:
        print(summary.profile_description)
        print()

    if not summary.results:
        print("No policy results found.")
        return

    for result in summary.results:
        print(f"- {result.policy} :: {result.status}")
        if result.target:
            print(f"    target: {result.target}")
        if result.severity:
            print(f"    severity: {result.severity}")
        if result.details:
            print(f"    details: {result.details}")
        print(f"    source: {result.source}")


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(main())
