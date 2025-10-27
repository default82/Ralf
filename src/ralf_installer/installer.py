"""Core installer routines."""

from __future__ import annotations

import dataclasses
import json
import secrets
import string
import urllib.error
import urllib.request
from typing import Iterable, List, Mapping, Sequence

from .config import Action, Component, Profile
from .providers import execute_action


@dataclasses.dataclass(slots=True)
class ExecutionReport:
    """Represents the result of an installer run."""

    planned_components: List[str]
    executed_components: List[str]
    skipped_components: List[str]

    def as_dict(self) -> dict[str, List[str]]:
        return {
            "planned_components": self.planned_components,
            "executed_components": self.executed_components,
            "skipped_components": self.skipped_components,
        }


@dataclasses.dataclass(slots=True)
class LoopScheduleSummary:
    """Summarises triggers configured for a specific automation loop."""

    loop: str
    description: str
    triggers: List[str]

    def as_dict(self) -> Mapping[str, object]:
        return {
            "loop": self.loop,
            "description": self.description,
            "triggers": list(self.triggers),
        }


@dataclasses.dataclass(slots=True)
class RetentionPolicy:
    """Represents an extracted retention policy from component actions."""

    component: str
    subject: str
    value: str
    provider: str | None

    def as_dict(self) -> Mapping[str, object]:
        payload: dict[str, object] = {
            "component": self.component,
            "subject": self.subject,
            "value": self.value,
        }
        if self.provider:
            payload["provider"] = self.provider
        return payload


class Installer:
    """High level coordinator that turns profiles into actionable steps."""

    def __init__(self, profile: Profile, *, dry_run: bool = False) -> None:
        self._profile = profile
        self._dry_run = dry_run

    @property
    def profile(self) -> Profile:
        return self._profile

    @property
    def dry_run(self) -> bool:
        return self._dry_run

    def plan(self) -> List[Component]:
        """Return components in the order they will be processed."""
        return self._profile.resolve_dependencies()

    def describe_loop_schedules(self) -> List[LoopScheduleSummary]:
        """Return declarative information about configured loop schedules."""

        scheduler = self._profile.scheduler
        if not scheduler:
            return []

        summaries: List[LoopScheduleSummary] = []
        for loop_name in sorted(scheduler.loops):
            schedule = scheduler.loops[loop_name]
            summaries.append(
                LoopScheduleSummary(
                    loop=loop_name,
                    description=schedule.description,
                    triggers=[trigger.describe() for trigger in schedule.triggers],
                )
            )
        return summaries

    def loop_schedule_report(self) -> Mapping[str, object]:
        """Return loop schedule metadata in a serialisable structure."""

        summaries = [summary.as_dict() for summary in self.describe_loop_schedules()]
        return {
            "profile": self._profile.name,
            "description": self._profile.description,
            "schedules": summaries,
        }

    def describe_retention_policies(self) -> List[RetentionPolicy]:
        """Return a list of retention policies discovered in the profile."""

        return _collect_retention_policies(self._profile.components)

    def retention_policy_report(self) -> Mapping[str, object]:
        """Return discovered retention policies in a serialisable structure."""

        policies = [policy.as_dict() for policy in self.describe_retention_policies()]
        return {
            "profile": self._profile.name,
            "description": self._profile.description,
            "retention_policies": policies,
        }

    def execute(self) -> ExecutionReport:
        """Execute the installer and return a detailed report."""
        ordered_components = self.plan()
        executed: List[str] = []
        skipped: List[str] = []

        for component in ordered_components:
            _run_component(component, dry_run=self._dry_run)
            if self._dry_run:
                skipped.append(component.name)
            else:
                executed.append(component.name)

        return ExecutionReport(
            planned_components=[component.name for component in ordered_components],
            executed_components=executed,
            skipped_components=skipped,
        )


def _run_component(component: Component, *, dry_run: bool) -> None:
    """Execute all actions for a component."""

    if component.actions:
        for action in component.actions:
            if action.provider == "vaultwarden":
                _execute_vaultwarden_action(action, dry_run=dry_run)
            else:
                execute_action(action, dry_run=dry_run)
    else:
        for task in component.tasks:
            _log_task(component.name, task, dry_run=dry_run)


def _log_task(component_name: str, task: str, *, dry_run: bool) -> None:
    prefix = "DRY-RUN" if dry_run else "EXEC"
    print(f"[{prefix}] {component_name}: {task}")


def _collect_retention_policies(components: Sequence[Component]) -> List[RetentionPolicy]:
    """Inspect components and extract retention related configuration entries."""

    policies: List[RetentionPolicy] = []
    for component in components:
        for action in component.actions:
            for subject, value in _find_retention_entries(action.options):
                policies.append(
                    RetentionPolicy(
                        component=component.name,
                        subject=subject or action.operation,
                        value=str(value),
                        provider=action.provider,
                    )
                )
    return policies


def _find_retention_entries(
    options: Mapping[str, object], *, prefix: str = ""
) -> List[tuple[str, object]]:
    """Recursively walk an options mapping and gather retention keys."""

    entries: List[tuple[str, object]] = []
    for key, value in options.items():
        path = f"{prefix}{key}" if not prefix else f"{prefix}.{key}"
        if "retention" in key.lower():
            entries.append((path, value))

        if isinstance(value, Mapping):
            entries.extend(_find_retention_entries(value, prefix=path))
        elif isinstance(value, Iterable) and not isinstance(value, (str, bytes, bytearray)):
            for index, item in enumerate(value):
                if isinstance(item, Mapping):
                    nested_prefix = f"{path}[{index}]"
                    entries.extend(_find_retention_entries(item, prefix=nested_prefix))

    return entries


def _execute_vaultwarden_action(action: Action, *, dry_run: bool) -> None:
    """Handle vaultwarden specific operations defined in profiles."""

    operation = action.operation
    options = dict(action.options)

    if operation == "rotate_secrets":
        _rotate_vaultwarden_secrets(options, dry_run=dry_run)
    else:  # pragma: no cover - defensive
        raise RuntimeError(f"Unsupported vaultwarden operation '{operation}'")


def _rotate_vaultwarden_secrets(options: Mapping[str, object], *, dry_run: bool) -> None:
    """Rotate Vaultwarden items according to the provided configuration."""

    base_url = _require_option(options, "url")
    token = _require_option(options, "access_token")
    raw_items = options.get("items")

    if not isinstance(raw_items, Iterable) or isinstance(raw_items, (str, bytes)):
        raise RuntimeError("Vaultwarden rotation requires an iterable 'items' list")

    items = list(raw_items)
    if not items:
        raise RuntimeError("Vaultwarden rotation list must not be empty")

    client = VaultwardenClient(str(base_url), str(token))

    for entry in items:
        if not isinstance(entry, Mapping):
            raise RuntimeError("Each vaultwarden item definition must be a mapping")

        item_id = str(_require_option(entry, "item_id"))
        label = str(entry.get("label", item_id))
        field_kind = str(entry.get("field", "password")).lower()
        length = int(entry.get("length", 32))
        alphabet = str(entry.get("alphabet", "alnum"))

        secret_value = _generate_secret(length, alphabet)

        if dry_run:
            _emit_vaultwarden(
                f"Would rotate {field_kind} for '{label}' (item={item_id}, length={length})"
            )
            continue

        if field_kind == "password":
            client.rotate_login_password(item_id, secret_value)
        elif field_kind == "field":
            field_name = str(_require_option(entry, "field_name"))
            client.rotate_custom_field(item_id, field_name, secret_value)
        else:
            raise RuntimeError(f"Unsupported vaultwarden field type '{field_kind}'")

        _emit_vaultwarden(
            f"Rotated {field_kind} for '{label}' (item={item_id}, length={length})"
        )


def _generate_secret(length: int, alphabet: str) -> str:
    if length <= 0:
        raise RuntimeError("Secret length must be greater than zero")

    alphabets = {
        "alnum": string.ascii_letters + string.digits,
        "hex": string.hexdigits.lower(),
        "symbols": string.ascii_letters + string.digits + string.punctuation,
    }
    charset = alphabets.get(alphabet, alphabet)
    if not charset:
        raise RuntimeError("Character set for secret generation must not be empty")

    return "".join(secrets.choice(charset) for _ in range(length))


def _require_option(options: Mapping[str, object], key: str) -> object:
    try:
        value = options[key]
    except KeyError as exc:  # pragma: no cover - defensive
        raise RuntimeError(f"Vaultwarden option '{key}' is required") from exc
    if value in (None, ""):
        raise RuntimeError(f"Vaultwarden option '{key}' must not be empty")
    return value


def _emit_vaultwarden(message: str) -> None:
    print(f"[VAULTWARDEN] {message}")


class VaultwardenClient:
    """Minimal client for interacting with the Vaultwarden HTTP API."""

    def __init__(self, base_url: str, token: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._token = token

    def rotate_login_password(self, cipher_id: str, password: str) -> None:
        cipher = self._get_cipher(cipher_id)
        login = cipher.get("login")
        if not isinstance(login, Mapping):
            raise RuntimeError(
                "Vaultwarden cipher does not contain a login object to rotate the password"
            )

        updated_cipher = dict(cipher)
        updated_login = dict(login)
        updated_login["password"] = password
        updated_cipher["login"] = updated_login

        self._update_cipher(cipher_id, updated_cipher)

    def rotate_custom_field(self, cipher_id: str, field_name: str, secret: str) -> None:
        cipher = self._get_cipher(cipher_id)
        fields = cipher.get("fields")
        if fields is None:
            fields_list: list[dict[str, object]] = []
        elif isinstance(fields, list):
            fields_list = [dict(field) for field in fields if isinstance(field, Mapping)]
        else:
            raise RuntimeError("Vaultwarden cipher fields must be a list")

        for field in fields_list:
            if field.get("name") == field_name:
                field["value"] = secret
                break
        else:
            fields_list.append({"name": field_name, "value": secret, "type": 0})

        updated_cipher = dict(cipher)
        updated_cipher["fields"] = fields_list
        self._update_cipher(cipher_id, updated_cipher)

    def _get_cipher(self, cipher_id: str) -> Mapping[str, object]:
        url = f"{self._base_url}/api/ciphers/{cipher_id}"
        request = urllib.request.Request(url, headers=self._headers())
        try:
            with urllib.request.urlopen(request) as response:  # type: ignore[no-untyped-call]
                payload = response.read()
        except urllib.error.HTTPError as exc:  # pragma: no cover - defensive
            raise RuntimeError(f"Failed to fetch cipher '{cipher_id}': {exc}") from exc

        try:
            data = json.loads(payload)
        except json.JSONDecodeError as exc:  # pragma: no cover - defensive
            raise RuntimeError("Vaultwarden returned invalid JSON") from exc

        if not isinstance(data, Mapping):
            raise RuntimeError("Vaultwarden cipher response must be a JSON object")
        return data

    def _update_cipher(self, cipher_id: str, payload: Mapping[str, object]) -> None:
        url = f"{self._base_url}/api/ciphers/{cipher_id}"
        data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            url, data=data, headers=self._headers(), method="PUT"
        )
        try:
            with urllib.request.urlopen(request) as response:  # type: ignore[no-untyped-call]
                if response.status not in (200, 201, 204):
                    raise RuntimeError(
                        f"Vaultwarden update for '{cipher_id}' returned unexpected status {response.status}"
                    )
        except urllib.error.HTTPError as exc:  # pragma: no cover - defensive
            raise RuntimeError(f"Failed to update cipher '{cipher_id}': {exc}") from exc

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._token}",
            "Content-Type": "application/json",
            "User-Agent": "ralf-installer/0.1",
        }
