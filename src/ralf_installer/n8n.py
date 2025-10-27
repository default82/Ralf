"""Utility helpers for interacting with the n8n REST API."""

from __future__ import annotations

import dataclasses
import json
import urllib.error
import urllib.request
from typing import Any, Iterable, Mapping, MutableMapping


class N8NError(RuntimeError):
    """Raised when communicating with the n8n REST API fails."""


@dataclasses.dataclass(slots=True)
class ImportResult:
    """Represents the outcome of importing a workflow into n8n."""

    name: str
    workflow_id: str
    created: bool
    activated: bool
    skipped: bool = False


class N8NClient:
    """Small convenience wrapper around the n8n REST API."""

    def __init__(self, base_url: str, api_key: str, *, timeout: float = 30.0) -> None:
        if not api_key:
            raise ValueError("An n8n API key is required")
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._timeout = timeout

    def list_workflows(self) -> list[Mapping[str, Any]]:
        """Return the list of workflows that currently exist."""

        payload = self._request("GET", "/workflows")
        if not isinstance(payload, Mapping):
            raise N8NError("Unexpected response when listing workflows")
        items = payload.get("data") or payload.get("workflows") or []
        if not isinstance(items, Iterable):
            raise N8NError("n8n returned an invalid workflow list")
        return list(items)

    def find_workflow_by_name(self, name: str) -> Mapping[str, Any] | None:
        """Return the workflow entry with the given name if it exists."""

        for entry in self.list_workflows():
            if not isinstance(entry, Mapping):
                continue
            if str(entry.get("name")) == name:
                return entry
        return None

    def import_workflow(
        self,
        export: Mapping[str, Any],
        *,
        activate: bool = False,
        overwrite: bool = True,
    ) -> ImportResult:
        """Create or update a workflow based on an exported definition."""

        payload = _sanitise_export(export)
        name = payload["name"]
        existing = self.find_workflow_by_name(name)

        response_payload: Mapping[str, Any] | None
        if existing:
            workflow_id = str(existing.get("id"))
            if not workflow_id:
                raise N8NError(f"Existing workflow '{name}' does not expose an id")
            if not overwrite:
                activated = bool(existing.get("active", False))
                if activate and not activated:
                    self.activate_workflow(workflow_id)
                    activated = True
                return ImportResult(
                    name=name,
                    workflow_id=workflow_id,
                    created=False,
                    activated=activated,
                    skipped=True,
                )
            raw_response = self._request("PATCH", f"/workflows/{workflow_id}", data=payload)
            response_payload = raw_response if isinstance(raw_response, Mapping) else None
            created = False
        else:
            raw_response = self._request("POST", "/workflows", data=payload)
            response_payload = raw_response if isinstance(raw_response, Mapping) else None
            workflow_id = ""
            if response_payload:
                workflow_id = str(
                    response_payload.get("id")
                    or (response_payload.get("data") or {}).get("id")
                )
            if not workflow_id:
                raise N8NError(f"n8n did not return an id for newly imported workflow '{name}'")
            created = True

        existing_active = bool(existing.get("active", False)) if existing else False
        response_active = bool(response_payload.get("active")) if response_payload else False
        activated = response_active or existing_active

        if activate and not activated:
            self.activate_workflow(workflow_id)
            activated = True
        elif not activate and activated and created:
            # Newly imported workflows should remain disabled unless requested
            self.deactivate_workflow(workflow_id)
            activated = False

        return ImportResult(
            name=name,
            workflow_id=workflow_id,
            created=created,
            activated=activated,
            skipped=False,
        )

    def activate_workflow(self, workflow_id: str) -> None:
        """Activate a workflow by id."""

        self._request("POST", f"/workflows/{workflow_id}/activate")

    def deactivate_workflow(self, workflow_id: str) -> None:
        """Deactivate a workflow by id."""

        self._request("POST", f"/workflows/{workflow_id}/deactivate")

    def delete_workflow(self, workflow_id: str) -> None:
        """Delete a workflow by id."""

        self._request("DELETE", f"/workflows/{workflow_id}")

    def delete_workflow_by_name(self, name: str, *, deactivate: bool = True) -> bool:
        """Delete a workflow by name if it exists."""

        existing = self.find_workflow_by_name(name)
        if not existing:
            return False

        workflow_id = str(existing.get("id"))
        if not workflow_id:
            raise N8NError(f"Workflow '{name}' does not expose an id")

        if deactivate and existing.get("active"):
            self.deactivate_workflow(workflow_id)
        self.delete_workflow(workflow_id)
        return True

    def _request(self, method: str, path: str, *, data: Mapping[str, Any] | None = None) -> Mapping[str, Any] | list[Any] | None:
        """Perform an HTTP request against the n8n REST API."""

        url = f"{self._base_url}/{path.lstrip('/') }"
        request = urllib.request.Request(url, method=method)
        request.add_header("Accept", "application/json")
        request.add_header("X-N8N-API-KEY", self._api_key)

        if data is not None:
            payload = json.dumps(data).encode("utf-8")
            request.add_header("Content-Type", "application/json")
            request.data = payload

        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                raw_body = response.read()
        except urllib.error.HTTPError as exc:  # pragma: no cover - defensive
            body = exc.read().decode("utf-8", "replace")
            message = f"{exc.code} {exc.reason}"
            if body:
                try:
                    payload = json.loads(body)
                except json.JSONDecodeError:
                    message = f"{message}: {body}"
                else:
                    if isinstance(payload, Mapping) and payload.get("message"):
                        message = f"{message}: {payload['message']}"
                    else:
                        message = f"{message}: {payload}"
            raise N8NError(message) from exc
        except urllib.error.URLError as exc:  # pragma: no cover - defensive
            raise N8NError(str(exc)) from exc

        if not raw_body:
            return None

        decoded = raw_body.decode("utf-8")
        if not decoded:
            return None
        try:
            return json.loads(decoded)
        except json.JSONDecodeError:
            raise N8NError("Failed to decode JSON response from n8n")


def _sanitise_export(export: Mapping[str, Any]) -> MutableMapping[str, Any]:
    """Reduce an export payload to fields accepted by the REST API."""

    if "name" not in export or not export["name"]:
        raise N8NError("Workflow export is missing a name")

    allowed_fields = {
        "name",
        "nodes",
        "connections",
        "settings",
        "pinData",
        "tags",
        "meta",
        "active",
    }
    payload: MutableMapping[str, Any] = {}
    for key in allowed_fields:
        if key in export:
            payload[key] = export[key]

    payload.setdefault("active", False)
    if "nodes" not in payload or "connections" not in payload:
        raise N8NError("Workflow export must contain nodes and connections")

    return payload


__all__ = ["ImportResult", "N8NClient", "N8NError"]
