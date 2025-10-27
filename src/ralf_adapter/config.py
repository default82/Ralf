"""Configuration models for the R.A.L.F. LLM adapter."""

from __future__ import annotations

from dataclasses import dataclass, field
import base64
import os
from pathlib import Path
from typing import Any, Dict, Mapping, Optional

import yaml

from .vault import VaultSecretReference


class AdapterConfigError(ValueError):
    """Raised when adapter configuration cannot be parsed."""


@dataclass(slots=True)
class VaultwardenSettings:
    """Settings for retrieving secrets from Vaultwarden."""

    base_url: str
    token: str


@dataclass(slots=True)
class RateLimitConfig:
    """Simple token bucket configuration for a model endpoint."""

    requests_per_minute: int

    @classmethod
    def from_mapping(cls, data: Mapping[str, Any]) -> "RateLimitConfig":
        try:
            rpm = int(data.get("requests_per_minute"))
        except (TypeError, ValueError) as exc:  # pragma: no cover - defensive
            raise AdapterConfigError("rate_limit.requests_per_minute must be an integer") from exc
        if rpm <= 0:
            raise AdapterConfigError("rate_limit.requests_per_minute must be greater than zero")
        return cls(requests_per_minute=rpm)


@dataclass(slots=True)
class ModelAuthConfig:
    """Authentication configuration for protected LLM endpoints."""

    scheme: str
    token: Optional[object] = None
    username: Optional[object] = None
    password: Optional[object] = None
    header_name: Optional[str] = None

    @classmethod
    def from_mapping(cls, data: Mapping[str, Any]) -> "ModelAuthConfig":
        scheme = str(data.get("type", "")).lower()
        if not scheme:
            raise AdapterConfigError("auth.type must be provided when auth is defined")
        token = data.get("token")
        username = data.get("username")
        password = data.get("password")
        header_name = data.get("header_name")
        return cls(
            scheme=scheme,
            token=_maybe_secret(token),
            username=_maybe_secret(username),
            password=_maybe_secret(password),
            header_name=str(header_name) if header_name else None,
        )

    def build_headers(self, resolver: "SecretResolver") -> Dict[str, str]:
        if self.scheme == "bearer":
            token = resolver.resolve(self.token)
            header = self.header_name or "Authorization"
            return {header: f"Bearer {token}"}
        if self.scheme == "basic":
            username = resolver.resolve(self.username)
            password = resolver.resolve(self.password)
            header = self.header_name or "Authorization"
            credentials = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
            return {header: f"Basic {credentials}"}
        if self.scheme == "header":
            token = resolver.resolve(self.token)
            header = self.header_name or "X-API-Key"
            return {header: token}
        raise AdapterConfigError(f"Unsupported auth.type '{self.scheme}'")


@dataclass(slots=True)
class ModelEndpointConfig:
    """Configuration for a single upstream model endpoint."""

    name: str
    url: str
    protocol: str = "generic"
    default_model: Optional[str] = None
    timeout: float = 30.0
    default_parameters: Mapping[str, Any] = field(default_factory=dict)
    headers: Mapping[str, object] = field(default_factory=dict)
    rate_limit: Optional[RateLimitConfig] = None
    auth: Optional[ModelAuthConfig] = None

    @classmethod
    def from_mapping(cls, name: str, data: Mapping[str, Any]) -> "ModelEndpointConfig":
        try:
            url = str(data["url"])
        except KeyError as exc:  # pragma: no cover - defensive
            raise AdapterConfigError(f"Endpoint '{name}' requires a 'url' attribute") from exc

        protocol = str(data.get("protocol", "generic")).lower()
        default_model = data.get("model")
        timeout_raw = data.get("timeout", 30)
        try:
            timeout = float(timeout_raw)
        except (TypeError, ValueError) as exc:  # pragma: no cover - defensive
            raise AdapterConfigError(
                f"Endpoint '{name}' timeout must be a number, got {timeout_raw!r}"
            ) from exc

        headers_raw = data.get("headers", {})
        default_params_raw = data.get("parameters", {})
        if headers_raw and not isinstance(headers_raw, Mapping):
            raise AdapterConfigError(f"Endpoint '{name}' headers must be a mapping")
        if default_params_raw and not isinstance(default_params_raw, Mapping):
            raise AdapterConfigError(f"Endpoint '{name}' parameters must be a mapping")

        rate_limit_raw = data.get("rate_limit")
        auth_raw = data.get("auth")

        headers = {str(key): _maybe_secret(value) for key, value in dict(headers_raw).items()}
        parameters = dict(default_params_raw) if isinstance(default_params_raw, Mapping) else {}
        rate_limit = (
            RateLimitConfig.from_mapping(rate_limit_raw)
            if isinstance(rate_limit_raw, Mapping)
            else None
        )
        auth = (
            ModelAuthConfig.from_mapping(auth_raw) if isinstance(auth_raw, Mapping) else None
        )

        return cls(
            name=name,
            url=url,
            protocol=protocol,
            default_model=str(default_model) if default_model else None,
            timeout=timeout,
            default_parameters=parameters,
            headers=headers,
            rate_limit=rate_limit,
            auth=auth,
        )

    def resolve(self, resolver: "SecretResolver") -> "ResolvedModelEndpoint":
        resolved_headers = {key: resolver.resolve(value) for key, value in self.headers.items()}
        if self.auth:
            resolved_headers.update(self.auth.build_headers(resolver))
        return ResolvedModelEndpoint(
            name=self.name,
            url=self.url,
            protocol=self.protocol,
            default_model=self.default_model,
            timeout=self.timeout,
            default_parameters=dict(self.default_parameters),
            headers=resolved_headers,
            rate_limit=self.rate_limit,
        )


@dataclass(slots=True)
class ResolvedModelEndpoint:
    """Endpoint configuration with secrets resolved to concrete values."""

    name: str
    url: str
    protocol: str
    default_model: Optional[str]
    timeout: float
    default_parameters: Mapping[str, Any]
    headers: Mapping[str, str]
    rate_limit: Optional[RateLimitConfig]

    def build_headers(self) -> Dict[str, str]:
        return dict(self.headers)


@dataclass(slots=True)
class AdapterConfig:
    """Top-level configuration for the adapter runtime."""

    endpoints: Dict[str, ModelEndpointConfig]
    default_endpoint: str
    vaultwarden: Optional[VaultwardenSettings] = None

    @classmethod
    def from_path(cls, path: Path) -> "AdapterConfig":
        if not path.exists():
            raise AdapterConfigError(f"Configuration file does not exist: {path}")
        with path.open("r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
        if not isinstance(data, Mapping):
            raise AdapterConfigError("Configuration root must be a mapping")
        return cls.from_mapping(data)

    @classmethod
    def from_mapping(cls, data: Mapping[str, Any]) -> "AdapterConfig":
        endpoints_raw = data.get("endpoints")
        if not isinstance(endpoints_raw, Mapping) or not endpoints_raw:
            raise AdapterConfigError("'endpoints' must be a non-empty mapping")

        endpoints: Dict[str, ModelEndpointConfig] = {}
        for name, entry in endpoints_raw.items():
            if not isinstance(entry, Mapping):
                raise AdapterConfigError(f"Endpoint '{name}' must be defined using a mapping")
            endpoint = ModelEndpointConfig.from_mapping(str(name), entry)
            endpoints[endpoint.name] = endpoint

        default_endpoint = str(data.get("default_endpoint", next(iter(endpoints))))
        if default_endpoint not in endpoints:
            raise AdapterConfigError(
                f"default_endpoint '{default_endpoint}' is not part of the endpoints section"
            )

        vault_settings = None
        if isinstance(data.get("vaultwarden"), Mapping):
            vault_settings = _parse_vaultwarden_settings(data["vaultwarden"])

        return cls(
            endpoints=endpoints,
            default_endpoint=default_endpoint,
            vaultwarden=vault_settings,
        )

    def resolve(self, *, env: Mapping[str, str] | None = None) -> "ResolvedAdapterConfig":
        env_mapping = env or os.environ
        token = None
        vault_provider = None
        if self.vaultwarden:
            token = _resolve_plain_secret(self.vaultwarden.token, env_mapping)
            vault_provider = SecretResolver.create_vault_provider(self.vaultwarden, token)
        resolver = SecretResolver(vault_provider=vault_provider, env=env_mapping)
        try:
            resolved = {
                name: endpoint.resolve(resolver) for name, endpoint in self.endpoints.items()
            }
        finally:
            if vault_provider is not None:
                vault_provider.close()
        return ResolvedAdapterConfig(endpoints=resolved, default_endpoint=self.default_endpoint)


@dataclass(slots=True)
class ResolvedAdapterConfig:
    """Adapter configuration that can be consumed by runtime services."""

    endpoints: Dict[str, ResolvedModelEndpoint]
    default_endpoint: str

    def get_endpoint(self, name: Optional[str]) -> ResolvedModelEndpoint:
        target = name or self.default_endpoint
        try:
            return self.endpoints[target]
        except KeyError as exc:
            raise AdapterConfigError(f"Unknown endpoint '{target}' requested") from exc


class SecretResolver:
    """Resolve secret placeholders embedded in endpoint configuration."""

    def __init__(
        self,
        *,
        vault_provider: Optional["VaultwardenSecretProvider"] = None,
        env: Mapping[str, str] | None = None,
    ) -> None:
        self._vault_provider = vault_provider
        self._env = env or {}

    @staticmethod
    def create_vault_provider(
        settings: VaultwardenSettings, token: str
    ) -> "VaultwardenSecretProvider":
        from .vault import VaultwardenSecretProvider

        return VaultwardenSecretProvider(settings.base_url, token)

    def resolve(self, value: object) -> str:
        if isinstance(value, VaultSecretReference):
            if not self._vault_provider:
                raise AdapterConfigError(
                    "Vaultwarden access is required to resolve vault:// references"
                )
            return self._vault_provider.read_secret(value)
        if isinstance(value, EnvSecretReference):
            env_value = self._env.get(value.variable)
            if env_value is None:
                raise AdapterConfigError(
                    f"Environment variable '{value.variable}' is required but not set"
                )
            return env_value
        if value is None:
            raise AdapterConfigError("Missing required secret value")
        return str(value)


@dataclass(slots=True)
class EnvSecretReference:
    """Reference to a secret stored in the environment."""

    variable: str


def _maybe_secret(value: object) -> object:
    if isinstance(value, str) and value.startswith("vault://"):
        try:
            return VaultSecretReference.parse(value)
        except ValueError as exc:  # pragma: no cover - defensive
            raise AdapterConfigError(str(exc)) from exc
    if isinstance(value, str) and value.startswith("env://"):
        variable = value.removeprefix("env://")
        if not variable:
            raise AdapterConfigError("env:// references must include a variable name")
        return EnvSecretReference(variable)
    return value


def _parse_vaultwarden_settings(data: Mapping[str, Any]) -> VaultwardenSettings:
    try:
        base_url = str(data["url"])
    except KeyError as exc:  # pragma: no cover - defensive
        raise AdapterConfigError("vaultwarden.url is required") from exc
    token_raw = data.get("access_token")
    if token_raw is None:
        raise AdapterConfigError("vaultwarden.access_token is required")
    token = _resolve_plain_secret(token_raw, os.environ)
    return VaultwardenSettings(base_url=base_url, token=token)


def _resolve_plain_secret(value: object, env: Mapping[str, str]) -> str:
    if isinstance(value, EnvSecretReference):
        resolved = env.get(value.variable)
        if resolved is None:
            raise AdapterConfigError(
                f"Environment variable '{value.variable}' is required but not set"
            )
        return resolved
    if isinstance(value, str):
        if value.startswith("vault://"):
            raise AdapterConfigError("vault:// cannot be used for vaultwarden.access_token")
        return value
    raise AdapterConfigError("Secret value must be a string or env:// reference")


__all__ = [
    "AdapterConfig",
    "AdapterConfigError",
    "ModelEndpointConfig",
    "ResolvedAdapterConfig",
    "ResolvedModelEndpoint",
    "VaultwardenSettings",
]
