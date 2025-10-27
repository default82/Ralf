"""Explainability helpers for learning artefacts and vector storage."""

from __future__ import annotations

import dataclasses
from typing import Iterable, List, Mapping, MutableMapping, Sequence


@dataclasses.dataclass(slots=True)
class VectorCollectionSpec:
    """Describe a vector collection used for knowledge retention."""

    name: str
    dimensions: int
    distance: str
    metadata: Mapping[str, str]
    on_disk: bool = False

    def as_dict(self) -> Mapping[str, object]:
        payload: MutableMapping[str, object] = {
            "name": self.name,
            "dimensions": self.dimensions,
            "distance": self.distance,
            "metadata": dict(self.metadata),
        }
        if self.on_disk:
            payload["on_disk"] = self.on_disk
        return payload

    def describe(self) -> str:
        metadata = ",".join(f"{key}:{value}" for key, value in self.metadata.items())
        storage = "on-disk" if self.on_disk else "in-memory"
        return (
            f"collection={self.name} dims={self.dimensions} distance={self.distance} "
            f"storage={storage} metadata=[{metadata}]"
        )


@dataclasses.dataclass(slots=True)
class VectorPipelineSpec:
    """Describe data ingestion pipelines feeding the vector database."""

    name: str
    source: str
    target_collection: str
    description: str | None = None

    def as_dict(self) -> Mapping[str, object]:
        payload: MutableMapping[str, object] = {
            "name": self.name,
            "source": self.source,
            "target_collection": self.target_collection,
        }
        if self.description:
            payload["description"] = self.description
        return payload

    def describe(self) -> str:
        base = f"pipeline={self.name} source={self.source} target={self.target_collection}"
        if self.description:
            base += f" description={self.description}"
        return base


@dataclasses.dataclass(slots=True)
class VectorBootstrapSummary:
    """Structured description of how the vector database is initialised."""

    host: str
    http_port: int
    grpc_port: int
    admin_secret: str | None
    snapshot_path: str | None
    collections: List[VectorCollectionSpec]
    pipelines: List[VectorPipelineSpec]

    def as_dict(self) -> Mapping[str, object]:
        payload: MutableMapping[str, object] = {
            "host": self.host,
            "http_port": self.http_port,
            "grpc_port": self.grpc_port,
            "collections": [collection.as_dict() for collection in self.collections],
            "pipelines": [pipeline.as_dict() for pipeline in self.pipelines],
        }
        if self.admin_secret:
            payload["admin_secret"] = self.admin_secret
        if self.snapshot_path:
            payload["snapshot_path"] = self.snapshot_path
        return payload

    def describe(self) -> str:
        parts = [f"vector-db={self.host}:{self.http_port}"]
        if self.admin_secret:
            parts.append(f"admin_secret={self.admin_secret}")
        if self.snapshot_path:
            parts.append(f"snapshots={self.snapshot_path}")
        parts.extend(collection.describe() for collection in self.collections)
        parts.extend(pipeline.describe() for pipeline in self.pipelines)
        return " ".join(parts)


@dataclasses.dataclass(slots=True)
class LearningPathway:
    """Describe how learning assets are shared across agents."""

    title: str
    source: str
    target: str
    artefacts: Sequence[str]

    def as_dict(self) -> Mapping[str, object]:
        return {
            "title": self.title,
            "source": self.source,
            "target": self.target,
            "artefacts": list(self.artefacts),
        }


@dataclasses.dataclass(slots=True)
class ExplainabilityReport:
    """Aggregated explainability metadata for documentation export."""

    profile: str
    description: str
    vector_bootstrap: List[VectorBootstrapSummary]
    learning_paths: List[LearningPathway]

    def as_dict(self) -> Mapping[str, object]:
        return {
            "profile": self.profile,
            "description": self.description,
            "vector_bootstrap": [entry.as_dict() for entry in self.vector_bootstrap],
            "learning_paths": [path.as_dict() for path in self.learning_paths],
        }


def parse_collections(definitions: Iterable[Mapping[str, object]]) -> List[VectorCollectionSpec]:
    """Convert raw profile definitions into collection specs."""

    collections: List[VectorCollectionSpec] = []
    for definition in definitions:
        name = str(definition.get("name"))
        if not name:
            raise RuntimeError("Vector collection requires a 'name'")
        try:
            dimensions_raw = definition["dimensions"]
        except KeyError as exc:  # pragma: no cover - defensive
            raise RuntimeError(f"Vector collection '{name}' is missing 'dimensions'") from exc
        dimensions = int(dimensions_raw)
        distance = str(definition.get("distance", "cosine"))
        on_disk = bool(definition.get("on_disk", False))
        metadata = _normalise_metadata(definition.get("metadata"))
        collections.append(
            VectorCollectionSpec(
                name=name,
                dimensions=dimensions,
                distance=distance,
                metadata=metadata,
                on_disk=on_disk,
            )
        )
    return collections


def parse_pipelines(definitions: Iterable[Mapping[str, object]]) -> List[VectorPipelineSpec]:
    """Convert raw pipeline definitions into pipeline specs."""

    pipelines: List[VectorPipelineSpec] = []
    for definition in definitions:
        name = str(definition.get("name"))
        if not name:
            raise RuntimeError("Vector pipeline requires a 'name'")
        target_collection = str(definition.get("target_collection"))
        if not target_collection:
            raise RuntimeError(
                f"Vector pipeline '{name}' is missing 'target_collection'"
            )
        source = str(definition.get("source", ""))
        description_raw = definition.get("description")
        description = str(description_raw) if description_raw not in (None, "") else None
        pipelines.append(
            VectorPipelineSpec(
                name=name,
                source=source,
                target_collection=target_collection,
                description=description,
            )
        )
    return pipelines


def build_bootstrap_summary(
    host: str,
    http_port: int,
    grpc_port: int,
    collections: Iterable[Mapping[str, object]],
    *,
    admin_secret: str | None = None,
    snapshot_path: str | None = None,
    pipelines: Iterable[Mapping[str, object]] | None = None,
) -> VectorBootstrapSummary:
    """Create a bootstrap summary from raw options."""

    parsed_collections = parse_collections(collections)
    parsed_pipelines = parse_pipelines(pipelines or [])
    return VectorBootstrapSummary(
        host=host,
        http_port=http_port,
        grpc_port=grpc_port,
        admin_secret=admin_secret,
        snapshot_path=snapshot_path,
        collections=parsed_collections,
        pipelines=parsed_pipelines,
    )


def build_learning_paths() -> List[LearningPathway]:
    """Return default learning pathways between agents for documentation."""

    return [
        LearningPathway(
            title="Incident → Knowledge Consolidation",
            source="A_MON (Prometheus/Loki Findings)",
            target="A_CODE · Vector-DB",
            artefacts=[
                "Anomalie-Beschreibungen",
                "Remediation-Playbooks",
                "Lessons Learned Markdown",
            ],
        ),
        LearningPathway(
            title="Deployment → Explainability",
            source="A_INFRA (OpenTofu/Ansible)",
            target="A_CODE · Ralf-Core",
            artefacts=[
                "Änderungs-Summary",
                "Impact-Analyse",
                "Verknüpfte Dashboards",
            ],
        ),
        LearningPathway(
            title="Planner Feedback Loop",
            source="A_PLAN · Foreman Discovery",
            target="Vector-DB · Forecast Pipelines",
            artefacts=[
                "Ressourcen-Simulationen",
                "Kapazitäts-Trends",
                "Empfohlene Platzierungspläne",
            ],
        ),
    ]


def render_report(
    profile: str,
    description: str,
    vector_bootstrap: Sequence[VectorBootstrapSummary],
    learning_paths: Sequence[LearningPathway] | None = None,
) -> ExplainabilityReport:
    """Compose an explainability report for external tooling."""

    return ExplainabilityReport(
        profile=profile,
        description=description,
        vector_bootstrap=list(vector_bootstrap),
        learning_paths=list(learning_paths or build_learning_paths()),
    )


def _normalise_metadata(raw: object) -> Mapping[str, str]:
    if raw in (None, ""):
        return {}
    if not isinstance(raw, Iterable) or isinstance(raw, (str, bytes)):
        raise RuntimeError("Vector collection metadata must be an iterable of mappings")

    metadata: dict[str, str] = {}
    for entry in raw:
        if not isinstance(entry, Mapping):
            raise RuntimeError("Vector collection metadata must be mappings")
        for key, value in entry.items():
            metadata[str(key)] = str(value)
    return metadata


__all__ = [
    "ExplainabilityReport",
    "LearningPathway",
    "VectorBootstrapSummary",
    "VectorCollectionSpec",
    "VectorPipelineSpec",
    "build_bootstrap_summary",
    "build_learning_paths",
    "parse_collections",
    "parse_pipelines",
    "render_report",
]

