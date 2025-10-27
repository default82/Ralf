import pathlib
import sys

import pytest
import yaml

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "src"))

from ralf_installer import cli  # noqa: E402

ASSETS_DIR = pathlib.Path(__file__).resolve().parents[2] / "installer" / "assets" / "testing"

AGENT_SCENARIOS = {
    "A_PLAN": {
        "template": "docker-compose.a_plan.yml",
        "services": {"planner", "postgres", "prometheus", "foreman-mock"},
    },
    "A_INFRA": {
        "template": "docker-compose.a_infra.yml",
        "services": {"infra", "gitea", "vaultwarden", "runner-queue"},
    },
    "A_MON": {
        "template": "docker-compose.a_mon.yml",
        "services": {"monitor", "prometheus", "loki", "grafana"},
    },
    "A_CODE": {
        "template": "docker-compose.a_code.yml",
        "services": {"code", "gitea", "qdrant"},
    },
    "A_SEC": {
        "template": "docker-compose.a_sec.yml",
        "services": {"security", "vaultwarden", "auditlog"},
    },
    "FOREMAN": {
        "template": "docker-compose.foreman.yml",
        "services": {"foreman", "dhcp-sim", "tftp-sim", "inventory-mock"},
    },
}


@pytest.fixture(params=sorted(AGENT_SCENARIOS.keys()), name="agent_scenario")
def fixture_agent_scenario(request):
    agent_name = request.param
    metadata = AGENT_SCENARIOS[agent_name]
    template_path = ASSETS_DIR / metadata["template"]
    if not template_path.exists():
        pytest.fail(f"Missing template for {agent_name}: {template_path}")

    payload = yaml.safe_load(template_path.read_text(encoding="utf-8"))
    return agent_name, template_path, payload, metadata


def test_template_contains_expected_services(agent_scenario):
    agent_name, _, payload, metadata = agent_scenario

    assert payload["version"].startswith("3")
    services = payload.get("services", {})
    assert services, f"No services defined for {agent_name}"

    for service in metadata["services"]:
        assert service in services, f"{service} missing in {agent_name} template"


def test_template_declares_shared_network(agent_scenario):
    _, _, payload, _ = agent_scenario
    networks = payload.get("networks", {})
    assert "ralf_testing" in networks


@pytest.mark.parametrize("command", ["destroy", "create"])
def test_cli_handles_missing_assets(monkeypatch, tmp_path, command):
    # Simulate missing assets by pointing the resolver to a temporary location.
    def missing_assets():
        raise FileNotFoundError("missing assets")

    monkeypatch.setattr(cli, "_resolve_testing_assets", missing_assets)
    with pytest.raises(SystemExit) as exc:
        cli.main(["test-env", command, "--target", str(tmp_path / "env")])
    assert exc.value.code == 2


def test_cli_create_and_destroy(tmp_path, monkeypatch):
    # ensure resolver points to real assets within the repository
    monkeypatch.setattr(cli, "_resolve_testing_assets", lambda: ASSETS_DIR)

    target = tmp_path / "env"

    result = cli.main(["test-env", "create", "--target", str(target)])
    assert result == 0

    for metadata in AGENT_SCENARIOS.values():
        copied = target / metadata["template"]
        assert copied.exists()

    # second run without force keeps existing environment
    result = cli.main(["test-env", "create", "--target", str(target)])
    assert result == 1

    # recreate with force
    result = cli.main(["test-env", "create", "--target", str(target), "--force"])
    assert result == 0

    # destroy removes directory
    result = cli.main(["test-env", "destroy", "--target", str(target)])
    assert result == 0
    assert not target.exists()

    # destroy again is a no-op
    result = cli.main(["test-env", "destroy", "--target", str(target)])
    assert result == 0
