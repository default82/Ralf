"""Documentation generator for installer profiles and execution reports."""

from __future__ import annotations

import datetime as _dt
import html
import pathlib
import re
from dataclasses import dataclass
from typing import Iterable, List, Sequence

from .config import Component, NodeDefinition, PlacementPolicy, Profile, WorkflowTemplate
from .explainability import VectorBootstrapSummary
from .installer import ExecutionReport, Installer, LoopScheduleSummary, RetentionPolicy


@dataclass(slots=True)
class _DocumentationContext:
    """Aggregated information required for report rendering."""

    profile: Profile
    report: ExecutionReport
    generated_at: _dt.datetime
    plan: Sequence[Component]
    nodes: Sequence[NodeDefinition]
    workflows: Sequence[WorkflowTemplate]
    schedules: Sequence[LoopScheduleSummary]
    retention: Sequence[RetentionPolicy]
    vector_bootstrap: Sequence[VectorBootstrapSummary]
    profile_path: pathlib.Path | None


def generate_documentation(
    installer: Installer,
    report: ExecutionReport,
    *,
    output_dir: pathlib.Path | None = None,
    profile_path: pathlib.Path | None = None,
) -> List[pathlib.Path]:
    """Generate Markdown and HTML documentation for an installer run.

    Parameters
    ----------
    installer:
        Installer instance that produced the report. Used to query metadata such
        as dependency plans and scheduling information.
    report:
        The execution report returned by the installer run.
    output_dir:
        Target directory for generated artefacts. Defaults to ``docs/generated``.
    profile_path:
        Optional filesystem path to the profile that was processed. Embedded in
        the generated output for traceability.
    """

    target_dir = pathlib.Path(output_dir) if output_dir else pathlib.Path("docs") / "generated"
    target_dir.mkdir(parents=True, exist_ok=True)

    now = _dt.datetime.now(tz=_dt.timezone.utc)
    profile = installer.profile
    context = _DocumentationContext(
        profile=profile,
        report=report,
        generated_at=now,
        plan=installer.plan(),
        nodes=tuple(profile.nodes),
        workflows=tuple(profile.workflows),
        schedules=tuple(installer.describe_loop_schedules()),
        retention=tuple(installer.describe_retention_policies()),
        vector_bootstrap=tuple(installer.describe_vector_bootstrap()),
        profile_path=profile_path,
    )

    slug = _slugify(profile.name)
    markdown_path = target_dir / f"{slug}.md"
    html_path = target_dir / f"{slug}.html"

    markdown = _render_markdown(context)
    html_output = _render_html(context)

    markdown_path.write_text(markdown, encoding="utf-8")
    html_path.write_text(html_output, encoding="utf-8")

    return [markdown_path, html_path]


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value).strip("-").lower()
    return slug or "profile-report"


def _render_markdown(context: _DocumentationContext) -> str:
    profile = context.profile
    lines: List[str] = []
    timestamp = context.generated_at.strftime("%Y-%m-%d %H:%M:%S %Z")

    lines.append(f"# Installer Report: {profile.name}")
    lines.append("")
    origin = _format_profile_origin(context.profile_path, profile.name)
    lines.append(f"_Erstellt am {timestamp} – Profil: {origin}_")
    lines.append("")
    if profile.description:
        lines.append(profile.description)
        lines.append("")

    lines.append("## Ausführungsübersicht")
    lines.append("")
    lines.extend(
        _render_markdown_summary_list(
            "Geplante Komponenten",
            context.report.planned_components,
        )
    )
    lines.extend(
        _render_markdown_summary_list(
            "Ausgeführte Komponenten",
            context.report.executed_components,
        )
    )
    lines.extend(
        _render_markdown_summary_list(
            "Übersprungene Komponenten",
            context.report.skipped_components,
        )
    )
    lines.append("")

    lines.append("## Komponenten")
    lines.append("")
    component_rows = [
        [
            component.name,
            component.description or "—",
            _markdown_multiline(_format_tasks(component.tasks)),
            _markdown_multiline(_format_dependencies(component.depends_on)),
            _markdown_multiline(_format_actions(component.actions)),
            _markdown_multiline(_describe_placement(component.placement)),
        ]
        for component in context.plan
    ]
    lines.extend(_markdown_table(["Name", "Beschreibung", "Aufgaben", "Abhängigkeiten", "Aktionen", "Platzierung"], component_rows))
    lines.append("")

    lines.append("## Knoten & Ressourcen")
    lines.append("")
    if context.nodes:
        node_rows = [
            [
                node.name,
                node.role or "—",
                _markdown_multiline(_format_mapping(node.labels) or "—"),
                _markdown_multiline(_describe_resources(node.capacity)),
            ]
            for node in context.nodes
        ]
        lines.extend(_markdown_table(["Name", "Rolle", "Labels", "Kapazität"], node_rows))
    else:
        lines.append("_Keine dedizierten Knoten im Profil hinterlegt._")
    lines.append("")

    lines.append("## Workflow-Vorlagen")
    lines.append("")
    if context.workflows:
        workflow_rows = [
            [
                workflow.name,
                workflow.loop,
                workflow.runtime,
                workflow.description or "—",
                _markdown_multiline(_format_list(workflow.inputs)),
                _markdown_multiline(_format_list(workflow.outputs)),
                _markdown_multiline(_format_list(workflow.phases)),
            ]
            for workflow in context.workflows
        ]
        lines.extend(
            _markdown_table(
                ["Name", "Loop", "Runtime", "Beschreibung", "Inputs", "Outputs", "Phasen"],
                workflow_rows,
            )
        )
    else:
        lines.append("_Keine Workflow-Vorlagen definiert._")
    lines.append("")

    lines.append("## Loop-Trigger")
    lines.append("")
    if context.schedules:
        for schedule in context.schedules:
            lines.append(f"- **{schedule.loop}** ({schedule.description or 'ohne Beschreibung'})")
            if schedule.triggers:
                for trigger in schedule.triggers:
                    lines.append(f"  - {trigger}")
            else:
                lines.append("  - _Keine Trigger konfiguriert._")
    else:
        lines.append("_Keine Scheduler-Informationen vorhanden._")
    lines.append("")

    lines.append("## Retention Policies")
    lines.append("")
    if context.retention:
        retention_rows = [
            [entry.component, entry.subject, entry.value, entry.provider or "—"]
            for entry in context.retention
        ]
        lines.extend(_markdown_table(["Komponente", "Feld", "Wert", "Provider"], retention_rows))
    else:
        lines.append("_Keine Retention-Parameter entdeckt._")
    lines.append("")

    lines.append("## Vector-Bootstrap")
    lines.append("")
    if context.vector_bootstrap:
        for entry in context.vector_bootstrap:
            base = f"- **{entry.host}:{entry.http_port}**"
            lines.append(base)
            lines.append(f"  - gRPC-Port: {entry.grpc_port}")
            if entry.admin_secret:
                lines.append(f"  - Admin-Secret: {entry.admin_secret}")
            if entry.snapshot_path:
                lines.append(f"  - Snapshots: {entry.snapshot_path}")
            if entry.collections:
                lines.append("  - Kollektionen:")
                for collection in entry.collections:
                    lines.append(f"    - {collection.describe()}")
            if entry.pipelines:
                lines.append("  - Pipelines:")
                for pipeline in entry.pipelines:
                    lines.append(f"    - {pipeline.describe()}")
    else:
        lines.append("_Keine Vector-Bootstrap-Einträge gefunden._")
    lines.append("")

    return "\n".join(lines).strip() + "\n"


def _render_markdown_summary_list(title: str, items: Sequence[str]) -> List[str]:
    formatted_items = ", ".join(f"`{item}`" for item in items) if items else "_Keine_"
    return [f"- {title}: {formatted_items}"]


def _markdown_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> List[str]:
    escaped_headers = [header.replace("|", "\\|") for header in headers]
    lines = ["| " + " | ".join(escaped_headers) + " |"]
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
    for row in rows:
        escaped = [cell.replace("|", "\\|") for cell in row]
        lines.append("| " + " | ".join(escaped) + " |")
    return lines


def _markdown_multiline(value: str) -> str:
    return value.replace("\n", "<br>") if value else "—"


def _render_html(context: _DocumentationContext) -> str:
    profile = context.profile
    timestamp = html.escape(context.generated_at.isoformat())
    origin = html.escape(_format_profile_origin(context.profile_path, profile.name))

    sections: List[str] = []
    sections.append("<section>")
    sections.append(f"  <h1>Installer Report: {html.escape(profile.name)}</h1>")
    sections.append(f"  <p><em>Erstellt am {timestamp} – Profil: {origin}</em></p>")
    if profile.description:
        sections.append(f"  <p>{html.escape(profile.description)}</p>")
    sections.append("</section>")

    sections.append("<section>")
    sections.append("  <h2>Ausführungsübersicht</h2>")
    sections.append("  <ul>")
    sections.append(_html_summary_item("Geplante Komponenten", context.report.planned_components))
    sections.append(_html_summary_item("Ausgeführte Komponenten", context.report.executed_components))
    sections.append(_html_summary_item("Übersprungene Komponenten", context.report.skipped_components))
    sections.append("  </ul>")
    sections.append("</section>")

    sections.append("<section>")
    sections.append("  <h2>Komponenten</h2>")
    sections.append(_html_table(
        ["Name", "Beschreibung", "Aufgaben", "Abhängigkeiten", "Aktionen", "Platzierung"],
        [
            [
                component.name,
                component.description or "—",
                _format_tasks(component.tasks),
                _format_dependencies(component.depends_on),
                _format_actions(component.actions),
                _describe_placement(component.placement),
            ]
            for component in context.plan
        ],
    ))
    sections.append("</section>")

    sections.append("<section>")
    sections.append("  <h2>Knoten &amp; Ressourcen</h2>")
    if context.nodes:
        sections.append(
            _html_table(
                ["Name", "Rolle", "Labels", "Kapazität"],
                [
                    [
                        node.name,
                        node.role or "—",
                        _format_mapping(node.labels) or "—",
                        _describe_resources(node.capacity),
                    ]
                    for node in context.nodes
                ],
            )
        )
    else:
        sections.append("  <p><em>Keine dedizierten Knoten im Profil hinterlegt.</em></p>")
    sections.append("</section>")

    sections.append("<section>")
    sections.append("  <h2>Workflow-Vorlagen</h2>")
    if context.workflows:
        sections.append(
            _html_table(
                ["Name", "Loop", "Runtime", "Beschreibung", "Inputs", "Outputs", "Phasen"],
                [
                    [
                        workflow.name,
                        workflow.loop,
                        workflow.runtime,
                        workflow.description or "—",
                        _format_list(workflow.inputs),
                        _format_list(workflow.outputs),
                        _format_list(workflow.phases),
                    ]
                    for workflow in context.workflows
                ],
            )
        )
    else:
        sections.append("  <p><em>Keine Workflow-Vorlagen definiert.</em></p>")
    sections.append("</section>")

    sections.append("<section>")
    sections.append("  <h2>Loop-Trigger</h2>")
    if context.schedules:
        sections.append("  <ul>")
        for schedule in context.schedules:
            description = schedule.description or "ohne Beschreibung"
            sections.append(
                f"    <li><strong>{html.escape(schedule.loop)}</strong> ({html.escape(description)})"
            )
            if schedule.triggers:
                sections.append("      <ul>")
                for trigger in schedule.triggers:
                    sections.append(f"        <li>{html.escape(trigger)}</li>")
                sections.append("      </ul>")
            sections.append("    </li>")
        sections.append("  </ul>")
    else:
        sections.append("  <p><em>Keine Scheduler-Informationen vorhanden.</em></p>")
    sections.append("</section>")

    sections.append("<section>")
    sections.append("  <h2>Retention Policies</h2>")
    if context.retention:
        sections.append(
            _html_table(
                ["Komponente", "Feld", "Wert", "Provider"],
                [
                    [entry.component, entry.subject, entry.value, entry.provider or "—"]
                    for entry in context.retention
                ],
            )
        )
    else:
        sections.append("  <p><em>Keine Retention-Parameter entdeckt.</em></p>")
    sections.append("</section>")

    sections.append("<section>")
    sections.append("  <h2>Vector-Bootstrap</h2>")
    if context.vector_bootstrap:
        sections.append("  <ul>")
        for entry in context.vector_bootstrap:
            sections.append(
                f"    <li><strong>{html.escape(entry.host)}:{entry.http_port}</strong>"
            )
            sections.append("      <ul>")
            sections.append(f"        <li>gRPC-Port: {entry.grpc_port}</li>")
            if entry.admin_secret:
                sections.append(
                    f"        <li>Admin-Secret: {html.escape(entry.admin_secret)}</li>"
                )
            if entry.snapshot_path:
                sections.append(
                    f"        <li>Snapshots: {html.escape(entry.snapshot_path)}</li>"
                )
            if entry.collections:
                sections.append("        <li>Kollektionen:<ul>")
                for collection in entry.collections:
                    sections.append(
                        f"          <li>{html.escape(collection.describe())}</li>"
                    )
                sections.append("        </ul></li>")
            if entry.pipelines:
                sections.append("        <li>Pipelines:<ul>")
                for pipeline in entry.pipelines:
                    sections.append(
                        f"          <li>{html.escape(pipeline.describe())}</li>"
                    )
                sections.append("        </ul></li>")
            sections.append("      </ul>")
            sections.append("    </li>")
        sections.append("  </ul>")
    else:
        sections.append("  <p><em>Keine Vector-Bootstrap-Einträge gefunden.</em></p>")
    sections.append("</section>")

    body = "\n".join(sections)
    return (
        "<!DOCTYPE html>\n"
        "<html lang=\"de\">\n"
        "  <head>\n"
        "    <meta charset=\"utf-8\">\n"
        "    <title>Installer Report: "
        + html.escape(profile.name)
        + "</title>\n"
        "    <style>body{font-family:system-ui, sans-serif;line-height:1.5;padding:2rem;}"
        "table{border-collapse:collapse;width:100%;margin-bottom:1.5rem;}"
        "th,td{border:1px solid #ddd;padding:0.5rem;vertical-align:top;}"
        "th{background:#f5f5f5;text-align:left;}"
        "section{margin-bottom:2rem;}"
        "code{background:#f2f2f2;padding:0 0.2rem;border-radius:3px;}"
        "ul{margin-top:0.5rem;margin-bottom:0.5rem;}"
        "</style>\n"
        "  </head>\n"
        "  <body>\n"
        f"{body}\n"
        "  </body>\n"
        "</html>\n"
    )


def _format_profile_origin(path: pathlib.Path | None, fallback: str) -> str:
    if path is None:
        return fallback
    try:
        return str(path.relative_to(pathlib.Path.cwd()))
    except ValueError:
        return str(path)


def _format_tasks(tasks: Sequence[str]) -> str:
    if not tasks:
        return "—"
    return "\n".join(f"• {task}" for task in tasks)


def _format_dependencies(dependencies: Sequence[str]) -> str:
    if not dependencies:
        return "—"
    return "\n".join(f"• {dependency}" for dependency in dependencies)


def _format_actions(actions: Sequence[object]) -> str:
    if not actions:
        return "—"
    formatted: List[str] = []
    for action in actions:
        provider = getattr(action, "provider", "")
        operation = getattr(action, "operation", "")
        formatted.append(f"• {provider}:{operation}")
    return "\n".join(formatted)


def _describe_placement(placement: PlacementPolicy | None) -> str:
    if placement is None:
        return "—"
    parts: List[str] = []
    if placement.required_labels:
        parts.append(
            "erforderlich="
            + ", ".join(f"{key}={value}" for key, value in placement.required_labels.items())
        )
    if placement.preferred_labels:
        parts.append(
            "bevorzugt="
            + ", ".join(f"{key}={value}" for key, value in placement.preferred_labels.items())
        )
    if placement.affinity:
        parts.append("Affinity=" + ", ".join(placement.affinity))
    if placement.anti_affinity:
        parts.append("Anti-Affinity=" + ", ".join(placement.anti_affinity))

    resource_summary = _describe_resources(placement.resources)
    if resource_summary:
        parts.append("Ressourcen=" + resource_summary)

    return "\n".join(f"• {part}" for part in parts) if parts else "—"


def _describe_resources(profile: object) -> str:
    if not hasattr(profile, "as_dict"):
        return "—"
    values = getattr(profile, "as_dict")()
    items = [f"{key}={value}" for key, value in values.items() if value]
    return ", ".join(items) if items else "—"


def _format_mapping(mapping: Iterable[tuple[str, str]] | dict[str, str]) -> str:
    if not mapping:
        return ""
    if isinstance(mapping, dict):
        items = mapping.items()
    else:
        items = mapping
    return "\n".join(f"{key}={value}" for key, value in items)


def _format_list(values: Sequence[str]) -> str:
    if not values:
        return "—"
    return "\n".join(values)


def _html_summary_item(title: str, items: Sequence[str]) -> str:
    if items:
        content = ", ".join(f"<code>{html.escape(item)}</code>" for item in items)
    else:
        content = "<em>Keine</em>"
    return f"    <li>{html.escape(title)}: {content}</li>"


def _html_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> str:
    header_html = "".join(f"<th>{html.escape(header)}</th>" for header in headers)
    body_rows: List[str] = []
    for row in rows:
        cells = "".join(f"<td>{_html_cell(cell)}</td>" for cell in row)
        body_rows.append(f"<tr>{cells}</tr>")
    if not body_rows:
        body_rows.append(
            f"<tr><td colspan=\"{len(headers)}\"><em>Keine Einträge</em></td></tr>"
        )
    table_lines = [
        "  <table>",
        f"    <thead><tr>{header_html}</tr></thead>",
        "    <tbody>" + "".join(body_rows) + "</tbody>",
        "  </table>",
    ]
    return "\n".join(table_lines)


def _html_cell(value: str) -> str:
    if not value or value == "—":
        return "<em>—</em>"
    escaped = html.escape(value)
    escaped = escaped.replace("\n", "<br>")
    escaped = escaped.replace("• ", "")
    return escaped

