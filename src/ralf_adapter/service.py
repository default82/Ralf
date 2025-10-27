"""Core service logic shared between REST and gRPC frontends."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Dict, List, Mapping, Optional

import httpx

from .config import AdapterConfig, ResolvedModelEndpoint
from .rate_limit import RateLimiter


@dataclass(slots=True)
class GenerationInput:
    """Canonical representation of a generation request."""

    prompt: str
    endpoint: Optional[str] = None
    model: Optional[str] = None
    parameters: Optional[Mapping[str, Any]] = None
    messages: Optional[List[Mapping[str, Any]]] = None
    metadata: Optional[Mapping[str, Any]] = None


@dataclass(slots=True)
class GenerationResult:
    """Normalized response returned from a model endpoint."""

    text: str
    model: Optional[str]
    endpoint: str
    latency_ms: int
    usage: Optional[Mapping[str, Any]]
    raw: Mapping[str, Any]


class RateLimitExceeded(RuntimeError):
    """Raised when an upstream limit would be exceeded."""


class AdapterError(RuntimeError):
    """Raised when the adapter cannot fulfil a request."""


class LLMAdapterService:
    """High level facade for interacting with configured model endpoints."""

    def __init__(self, config: AdapterConfig) -> None:
        self._config = config
        self._resolved = config.resolve()
        self._client = httpx.AsyncClient()
        self._limiters: Dict[str, RateLimiter] = {}
        self._configure_limiters()

    async def aclose(self) -> None:
        await self._client.aclose()

    async def generate(self, request: GenerationInput) -> GenerationResult:
        endpoint = self._resolved.get_endpoint(request.endpoint)
        limiter = self._limiters.get(endpoint.name)
        if limiter is not None:
            acquired = await limiter.try_acquire()
            if not acquired:
                raise RateLimitExceeded(
                    f"Rate limit exceeded for endpoint '{endpoint.name}'"
                )

        payload = _build_payload(endpoint, request)
        headers = endpoint.build_headers()
        start = time.perf_counter()
        try:
            response = await self._client.post(
                endpoint.url,
                json=payload,
                headers=headers,
                timeout=endpoint.timeout,
            )
        except httpx.HTTPError as exc:
            raise AdapterError(
                f"Failed to contact endpoint '{endpoint.name}': {exc!s}"
            ) from exc

        if response.status_code >= 400:
            raise AdapterError(
                f"Endpoint '{endpoint.name}' returned HTTP {response.status_code}: {response.text[:200]}"
            )

        try:
            data = response.json()
        except ValueError as exc:  # pragma: no cover - defensive
            raise AdapterError("Endpoint response is not valid JSON") from exc

        text = _extract_text(endpoint.protocol, data)
        latency_ms = int((time.perf_counter() - start) * 1000)
        model = payload.get("model") or endpoint.default_model
        usage = data.get("usage") if isinstance(data, Mapping) else None
        return GenerationResult(
            text=text,
            model=model if isinstance(model, str) else None,
            endpoint=endpoint.name,
            latency_ms=latency_ms,
            usage=usage if isinstance(usage, Mapping) else None,
            raw=data if isinstance(data, Mapping) else {"data": data},
        )

    def reload(self, config: AdapterConfig) -> None:
        """Reload runtime configuration without creating a new instance."""

        self._config = config
        self._resolved = config.resolve()
        self._configure_limiters()

    def _configure_limiters(self) -> None:
        self._limiters.clear()
        for endpoint in self._resolved.endpoints.values():
            if endpoint.rate_limit:
                limiter = RateLimiter.per_minute(endpoint.rate_limit.requests_per_minute)
                self._limiters[endpoint.name] = limiter


def _build_payload(endpoint: ResolvedModelEndpoint, request: GenerationInput) -> Dict[str, Any]:
    params: Dict[str, Any] = dict(endpoint.default_parameters)
    if request.parameters:
        params.update(request.parameters)

    if endpoint.protocol == "openai":
        model_name = request.model or endpoint.default_model
        if not model_name:
            raise AdapterError(
                f"Endpoint '{endpoint.name}' requires a model to be specified"
            )
        messages = request.messages
        if not messages:
            messages = [{"role": "user", "content": request.prompt}]
        payload: Dict[str, Any] = {
            "model": model_name,
            "messages": messages,
        }
        payload.update(params)
        if request.metadata:
            payload["metadata"] = request.metadata
        return payload

    payload = {"prompt": request.prompt}
    if request.model or endpoint.default_model:
        payload["model"] = request.model or endpoint.default_model
    if params:
        payload["parameters"] = params
    if request.metadata:
        payload["metadata"] = request.metadata
    if request.messages:
        payload["messages"] = request.messages
    return payload


def _extract_text(protocol: str, data: Mapping[str, Any]) -> str:
    if protocol == "openai":
        choices = data.get("choices")
        if isinstance(choices, list) and choices:
            first = choices[0]
            if isinstance(first, Mapping):
                message = first.get("message")
                if isinstance(message, Mapping):
                    content = message.get("content")
                    if isinstance(content, str):
                        return content
                text_value = first.get("text")
                if isinstance(text_value, str):
                    return text_value
        raise AdapterError("OpenAI-compatible response did not include choices")

    text = data.get("text")
    if isinstance(text, str):
        return text
    completion = data.get("completion")
    if isinstance(completion, Mapping):
        inner_text = completion.get("text")
        if isinstance(inner_text, str):
            return inner_text
    if isinstance(completion, str):
        return completion
    raise AdapterError("Endpoint response did not include a text field")


__all__ = [
    "AdapterError",
    "GenerationInput",
    "GenerationResult",
    "LLMAdapterService",
    "RateLimitExceeded",
]
