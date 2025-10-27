import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src"))

from ralf_installer.config import Profile  # noqa: E402
from ralf_installer import planner  # noqa: E402


PROFILE_PATH = pathlib.Path(__file__).resolve().parents[1] / "installer" / "profiles" / "core.yaml"


def test_distributed_plan_assigns_components():
    profile = Profile.load(PROFILE_PATH)
    components = profile.resolve_dependencies()
    plan = planner.plan_distributed_deployment(components, profile.nodes)

    assert plan.unsatisfied_requirements == []

    assignments = {decision.component: decision.node for decision in plan.decisions if decision.node}

    assert assignments["postgresql"] == "pve01"
    assert assignments["gitea"] == "pve01"
    assert assignments["vector-db"] == "pve01"
    assert assignments["ralf-ui"] == "pve01"
    assert assignments["vaultwarden"] == "pve02"
    assert assignments["automation"] == "pve02"
    assert assignments["observability"] == "pve02"
    assert assignments["backups"] == "pbs01"

    assert assignments["postgresql"] != assignments["vaultwarden"]

    assert plan.node_usage["pve01"].cpu == pytest.approx(20.0)
    assert plan.node_usage["pve02"].cpu == pytest.approx(12.0)
    assert plan.node_usage["pbs01"].storage_gb == pytest.approx(2000.0)


def test_scaling_simulation_identifies_cpu_pressure():
    profile = Profile.load(PROFILE_PATH)
    components = profile.resolve_dependencies()
    plan = planner.plan_distributed_deployment(components, profile.nodes)

    simulation = planner.simulate_scaling(
        plan,
        components,
        {"vector-db": 2.0, "observability": 3.0},
    )

    deficits = {(item.node, item.resource): item for item in simulation.deficits}

    assert ("pve01", "cpu") in deficits
    assert ("pve02", "cpu") in deficits
    assert ("pve02", "network_gbps") in deficits

    assert deficits[("pve01", "cpu")].required == pytest.approx(28.0)
    assert deficits[("pve01", "cpu")].available == pytest.approx(24.0)
    assert deficits[("pve02", "cpu")].required == pytest.approx(24.0)
    assert deficits[("pve02", "cpu")].available == pytest.approx(16.0)
    assert deficits[("pve02", "network_gbps")].required == pytest.approx(15.0)
    assert deficits[("pve02", "network_gbps")].available == pytest.approx(12.0)

    assert simulation.usage["pve01"].cpu == pytest.approx(28.0)
    assert simulation.usage["pve02"].cpu == pytest.approx(24.0)
