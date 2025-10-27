"""Resource planning and distributed deployment helpers."""

from __future__ import annotations

import dataclasses
from typing import Dict, Iterable, List, Mapping, Sequence

from .config import Component, NodeDefinition, PlacementPolicy, ResourceProfile


@dataclasses.dataclass(slots=True)
class PlacementDecision:
    """Represents the placement outcome for a single component."""

    component: str
    node: str | None
    score: float
    reasons: List[str]
    required: bool

    def as_dict(self) -> Mapping[str, object]:
        return {
            "component": self.component,
            "node": self.node,
            "score": round(self.score, 4),
            "reasons": list(self.reasons),
            "required": self.required,
        }


@dataclasses.dataclass(slots=True)
class DistributedPlan:
    """Describes the placement of components across the available nodes."""

    decisions: List[PlacementDecision]
    placements: Mapping[str, str]
    node_usage: Mapping[str, ResourceProfile]
    node_capacity: Mapping[str, ResourceProfile]

    @property
    def unsatisfied_requirements(self) -> List[str]:
        return [
            decision.component
            for decision in self.decisions
            if decision.required and decision.node is None
        ]

    def assignment_for(self, component: str) -> str | None:
        for decision in self.decisions:
            if decision.component == component:
                return decision.node
        raise KeyError(f"Unknown component '{component}'")

    def as_dict(self, *, profile: str, description: str) -> Mapping[str, object]:
        return {
            "profile": profile,
            "description": description,
            "decisions": [decision.as_dict() for decision in self.decisions],
            "nodes": [
                {
                    "name": name,
                    "capacity": self.node_capacity[name].as_dict(),
                    "usage": self.node_usage[name].as_dict(),
                }
                for name in sorted(self.node_capacity)
            ],
            "placements": dict(self.placements),
            "unsatisfied_requirements": list(self.unsatisfied_requirements),
        }


@dataclasses.dataclass(slots=True)
class ScalingDeficit:
    """Represents a resource deficit observed during scaling."""

    node: str
    resource: str
    required: float
    available: float

    def as_dict(self) -> Mapping[str, float | str]:
        return {
            "node": self.node,
            "resource": self.resource,
            "required": round(self.required, 4),
            "available": round(self.available, 4),
        }


@dataclasses.dataclass(slots=True)
class ScalingSimulation:
    """Result of a scaling simulation."""

    plan: DistributedPlan
    usage: Mapping[str, ResourceProfile]
    capacity: Mapping[str, ResourceProfile]
    deficits: List[ScalingDeficit]

    def as_dict(self) -> Mapping[str, object]:
        return {
            "nodes": [
                {
                    "name": name,
                    "capacity": self.capacity[name].as_dict(),
                    "usage": self.usage[name].as_dict(),
                }
                for name in sorted(self.capacity)
            ],
            "deficits": [deficit.as_dict() for deficit in self.deficits],
        }


def plan_distributed_deployment(
    components: Sequence[Component], nodes: Sequence[NodeDefinition]
) -> DistributedPlan:
    """Return a distributed deployment plan for the provided components."""

    node_capacity: Dict[str, ResourceProfile] = {
        node.name: node.capacity.clone() for node in nodes
    }
    node_states: Dict[str, ResourceProfile] = {
        name: capacity.clone() for name, capacity in node_capacity.items()
    }
    node_usage: Dict[str, ResourceProfile] = {
        name: ResourceProfile() for name in node_capacity
    }

    placements: Dict[str, str] = {}
    decisions: List[PlacementDecision] = []

    for component in components:
        policy = component.placement
        if not policy:
            decisions.append(
                PlacementDecision(
                    component=component.name,
                    node=None,
                    score=0.0,
                    reasons=["no placement policy defined"],
                    required=False,
                )
            )
            continue

        decision = _schedule_component(
            component, policy, nodes, node_states, placements
        )
        decisions.append(decision)
        if decision.node:
            placements[component.name] = decision.node
            usage_profile = node_usage[decision.node]
            usage_profile.add_inplace(policy.resources)
            node_states[decision.node].consume(policy.resources)

    for node in nodes:
        node_usage.setdefault(node.name, ResourceProfile())

    return DistributedPlan(
        decisions=decisions,
        placements=placements,
        node_usage=node_usage,
        node_capacity=node_capacity,
    )


def simulate_scaling(
    plan: DistributedPlan,
    components: Sequence[Component],
    scale_overrides: Mapping[str, float],
) -> ScalingSimulation:
    """Simulate resource usage for the provided scale overrides."""

    component_lookup = {component.name: component for component in components}
    usage: Dict[str, ResourceProfile] = {
        name: ResourceProfile() for name in plan.node_capacity
    }

    for decision in plan.decisions:
        if decision.node is None:
            continue
        component = component_lookup.get(decision.component)
        if not component or not component.placement:
            continue
        factor = float(scale_overrides.get(component.name, 1.0))
        demand = component.placement.resources.scaled(factor)
        usage_profile = usage.setdefault(decision.node, ResourceProfile())
        usage_profile.add_inplace(demand)

    deficits: List[ScalingDeficit] = []
    for node, capacity in plan.node_capacity.items():
        used = usage.setdefault(node, ResourceProfile())
        deficits.extend(_calculate_deficits(node, used, capacity))

    return ScalingSimulation(plan=plan, usage=usage, capacity=plan.node_capacity, deficits=deficits)


def _schedule_component(
    component: Component,
    policy: PlacementPolicy,
    nodes: Sequence[NodeDefinition],
    node_states: Mapping[str, ResourceProfile],
    placements: Mapping[str, str],
) -> PlacementDecision:
    best_choice: tuple[float, NodeDefinition, List[str]] | None = None
    rejection_reasons: List[str] = []

    for node in nodes:
        reasons: List[str] = []
        missing = _missing_required(policy.required_labels, node.labels)
        if missing:
            rejection_reasons.append(f"{node.name}: missing {'/'.join(missing)}")
            continue

        remaining = node_states[node.name]
        if not remaining.can_host(policy.resources):
            rejection_reasons.append(f"{node.name}: insufficient capacity")
            continue

        if _violates_anti_affinity(policy, placements, node.name):
            rejection_reasons.append(f"{node.name}: anti-affinity conflict")
            continue

        score, scoring_reasons = _score_node(node, remaining, policy, placements)
        reasons.extend(scoring_reasons)

        if best_choice is None or score > best_choice[0] or (
            score == best_choice[0] and node.name < best_choice[1].name
        ):
            best_choice = (score, node, reasons)

    if best_choice is None:
        reason = "no matching nodes"
        if rejection_reasons:
            reason = "; ".join(rejection_reasons)
        return PlacementDecision(
            component=component.name,
            node=None,
            score=0.0,
            reasons=[reason],
            required=True,
        )

    score, node, reasons = best_choice
    return PlacementDecision(
        component=component.name,
        node=node.name,
        score=score,
        reasons=reasons,
        required=True,
    )


def _missing_required(
    required: Mapping[str, str], labels: Mapping[str, str]
) -> List[str]:
    missing: List[str] = []
    for key, value in required.items():
        if labels.get(key) != value:
            missing.append(f"{key}={value}")
    return missing


def _violates_anti_affinity(
    policy: PlacementPolicy, placements: Mapping[str, str], node_name: str
) -> bool:
    for component in policy.anti_affinity:
        if placements.get(component) == node_name:
            return True
    return False


def _score_node(
    node: NodeDefinition,
    remaining: ResourceProfile,
    policy: PlacementPolicy,
    placements: Mapping[str, str],
) -> tuple[float, List[str]]:
    score = 1.0
    reasons: List[str] = []

    for key, value in policy.preferred_labels.items():
        if node.labels.get(key) == value:
            score += 5.0
            reasons.append(f"preferred label {key}={value}")

    headroom = _headroom_ratio(remaining, policy.resources)
    score += min(headroom, 10.0)
    reasons.append(f"headroom {headroom:.2f}")

    affinity_bonus = 0.0
    satisfied_affinity: List[str] = []
    for component in policy.affinity:
        assigned = placements.get(component)
        if assigned == node.name:
            affinity_bonus += 8.0
            satisfied_affinity.append(component)
        elif assigned:
            score -= 2.0
            reasons.append(f"affinity prefers {component} on this node")
    if affinity_bonus:
        score += affinity_bonus
        reasons.append(f"affinity with {', '.join(satisfied_affinity)}")

    return score, reasons


def _headroom_ratio(remaining: ResourceProfile, demand: ResourceProfile) -> float:
    ratios: List[float] = []
    if demand.cpu > 0:
        ratios.append(remaining.cpu / demand.cpu)
    if demand.memory_gb > 0:
        ratios.append(remaining.memory_gb / demand.memory_gb)
    if demand.storage_gb > 0:
        ratios.append(remaining.storage_gb / demand.storage_gb)
    if demand.network_gbps > 0:
        ratios.append(remaining.network_gbps / demand.network_gbps)
    if not ratios:
        return 10.0
    return min(ratios)


def _calculate_deficits(
    node: str, used: ResourceProfile, capacity: ResourceProfile
) -> List[ScalingDeficit]:
    deficits: List[ScalingDeficit] = []
    epsilon = 1e-9
    if used.cpu > capacity.cpu + epsilon:
        deficits.append(
            ScalingDeficit(
                node=node,
                resource="cpu",
                required=used.cpu,
                available=capacity.cpu,
            )
        )
    if used.memory_gb > capacity.memory_gb + epsilon:
        deficits.append(
            ScalingDeficit(
                node=node,
                resource="memory_gb",
                required=used.memory_gb,
                available=capacity.memory_gb,
            )
        )
    if used.storage_gb > capacity.storage_gb + epsilon:
        deficits.append(
            ScalingDeficit(
                node=node,
                resource="storage_gb",
                required=used.storage_gb,
                available=capacity.storage_gb,
            )
        )
    if used.network_gbps > capacity.network_gbps + epsilon:
        deficits.append(
            ScalingDeficit(
                node=node,
                resource="network_gbps",
                required=used.network_gbps,
                available=capacity.network_gbps,
            )
        )
    return deficits


__all__ = [
    "DistributedPlan",
    "PlacementDecision",
    "ScalingDeficit",
    "ScalingSimulation",
    "plan_distributed_deployment",
    "simulate_scaling",
]
