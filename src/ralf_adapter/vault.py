"""Utilities for resolving secrets from Vaultwarden."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Mapping

import httpx


@dataclass(slots=True)
class VaultSecretReference:
    """Reference to a secret stored inside Vaultwarden."""

    cipher_id: str
    field: str
    kind: str = "password"

    @classmethod
    def parse(cls, reference: str) -> "VaultSecretReference":
        if not reference.startswith("vault://"):
            raise ValueError("Vault secret references must start with 'vault://'")
        path = reference.removeprefix("vault://")
        if "#" in path:
            cipher_id, field = path.split("#", 1)
        else:
            parts = path.split("/")
            if len(parts) < 2:
                raise ValueError(
                    "Vault secret references must include both cipher id and field"
                )
            cipher_id = "/".join(parts[:-1])
            field = parts[-1]
        cipher_id = cipher_id.strip()
        field = field.strip()
        if not cipher_id or not field:
            raise ValueError("Vault secret references require both cipher and field")
        if field.startswith("field:"):
            return cls(cipher_id=cipher_id, field=field.split(":", 1)[1], kind="field")
        return cls(cipher_id=cipher_id, field=field, kind="password")


class VaultwardenSecretProvider:
    """Small helper that fetches secret values from Vaultwarden."""

    def __init__(
        self,
        base_url: str,
        token: str,
        *,
        timeout: float = 10.0,
    ) -> None:
        self._client = httpx.Client(
            base_url=base_url.rstrip("/"),
            headers={
                "Authorization": f"Bearer {token}",
                "User-Agent": "ralf-adapter/0.1",
            },
            timeout=timeout,
        )
        self._cache: Dict[str, Mapping[str, object]] = {}

    def read_secret(self, reference: VaultSecretReference) -> str:
        cipher = self._get_cipher(reference.cipher_id)
        if reference.kind == "password":
            login = cipher.get("login")
            if not isinstance(login, Mapping) or "password" not in login:
                raise RuntimeError(
                    f"Cipher '{reference.cipher_id}' does not expose a login password"
                )
            password = login.get("password")
            if not isinstance(password, str):
                raise RuntimeError("Vaultwarden password must be a string")
            return password
        if reference.kind == "field":
            fields = cipher.get("fields", [])
            if not isinstance(fields, list):
                raise RuntimeError("Vaultwarden custom fields must be stored as a list")
            for field in fields:
                if isinstance(field, Mapping) and field.get("name") == reference.field:
                    value = field.get("value")
                    if isinstance(value, str):
                        return value
                    raise RuntimeError(
                        f"Vaultwarden field '{reference.field}' is not stored as text"
                    )
            raise RuntimeError(
                f"Vaultwarden cipher '{reference.cipher_id}' is missing field '{reference.field}'"
            )
        raise RuntimeError(f"Unsupported Vault secret kind '{reference.kind}'")

    def _get_cipher(self, cipher_id: str) -> Mapping[str, object]:
        if cipher_id not in self._cache:
            try:
                response = self._client.get(f"/api/ciphers/{cipher_id}")
                response.raise_for_status()
            except httpx.HTTPError as exc:
                raise RuntimeError(
                    f"Failed to fetch Vaultwarden cipher '{cipher_id}': {exc!s}"
                ) from exc
            try:
                payload = response.json()
            except ValueError as exc:
                raise RuntimeError("Vaultwarden cipher response is not valid JSON") from exc
            if not isinstance(payload, Mapping):
                raise RuntimeError("Vaultwarden cipher response must be a JSON object")
            self._cache[cipher_id] = payload
        return self._cache[cipher_id]

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "VaultwardenSecretProvider":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


__all__ = ["VaultSecretReference", "VaultwardenSecretProvider"]
