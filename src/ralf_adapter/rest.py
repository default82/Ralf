"""FastAPI application exposing the adapter via REST."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .config import AdapterConfig
from .service import (
    AdapterError,
    GenerationInput,
    GenerationResult,
    LLMAdapterService,
    RateLimitExceeded,
)


class GeneratePayload(BaseModel):
    """Schema for POST /v1/generate."""

    prompt: str = Field(..., description="User prompt or question")
    endpoint: Optional[str] = Field(
        default=None,
        description="Name of the configured endpoint to target",
    )
    model: Optional[str] = Field(
        default=None,
        description="Override the default model for the endpoint",
    )
    parameters: Optional[Dict[str, Any]] = Field(
        default=None,
        description="Additional inference parameters forwarded upstream",
    )
    messages: Optional[List[Dict[str, Any]]] = Field(
        default=None,
        description="Optional chat history used by chat-capable models",
    )
    metadata: Optional[Dict[str, Any]] = Field(
        default=None,
        description="Opaque metadata forwarded to upstream services",
    )

    def to_domain(self) -> GenerationInput:
        return GenerationInput(
            prompt=self.prompt,
            endpoint=self.endpoint,
            model=self.model,
            parameters=self.parameters,
            messages=self.messages,
            metadata=self.metadata,
        )


class GenerateResponse(BaseModel):
    """Standard response body for successful generations."""

    text: str
    model: Optional[str]
    endpoint: str
    latency_ms: int
    usage: Optional[Dict[str, Any]]
    raw: Dict[str, Any]

    @classmethod
    def from_result(cls, result: GenerationResult) -> "GenerateResponse":
        return cls(
            text=result.text,
            model=result.model,
            endpoint=result.endpoint,
            latency_ms=result.latency_ms,
            usage=dict(result.usage) if result.usage is not None else None,
            raw=dict(result.raw),
        )


def create_app(config: AdapterConfig) -> FastAPI:
    """Instantiate a FastAPI app backed by ``LLMAdapterService``."""

    service = LLMAdapterService(config)
    app = FastAPI(title="R.A.L.F. LLM Adapter", version="0.1.0")

    @app.on_event("shutdown")
    async def _shutdown() -> None:  # pragma: no cover - lifecycle hook
        await service.aclose()

    @app.get("/healthz", tags=["system"])
    async def health() -> Dict[str, str]:
        return {"status": "ok"}

    @app.post("/v1/generate", response_model=GenerateResponse, tags=["generation"])
    async def generate(payload: GeneratePayload) -> GenerateResponse:
        try:
            result = await service.generate(payload.to_domain())
        except RateLimitExceeded as exc:
            raise HTTPException(status_code=429, detail=str(exc)) from exc
        except AdapterError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        return GenerateResponse.from_result(result)

    return app


__all__ = ["create_app", "GeneratePayload", "GenerateResponse"]
