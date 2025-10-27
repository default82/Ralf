"""gRPC server exposing the adapter functionality."""

from __future__ import annotations

from typing import Any, Dict, Optional

import grpc
from google.protobuf import json_format, struct_pb2

from .config import AdapterConfig
from .service import (
    AdapterError,
    GenerationInput,
    GenerationResult,
    LLMAdapterService,
    RateLimitExceeded,
)


class AdapterGrpcServer:
    """Wraps ``LLMAdapterService`` in a gRPC transport."""

    def __init__(self, service: LLMAdapterService) -> None:
        self._service = service

    async def serve(self, host: str = "0.0.0.0", port: int = 50051) -> None:
        server = grpc.aio.server()
        handler = grpc.method_handlers_generic_handler(
            "ralf.adapter.v1.LLMAdapter",
            {
                "Generate": grpc.unary_unary_rpc_method_handler(
                    self._generate,
                    request_deserializer=struct_pb2.Struct.FromString,
                    response_serializer=struct_pb2.Struct.SerializeToString,
                )
            },
        )
        server.add_generic_rpc_handlers((handler,))
        server.add_insecure_port(f"{host}:{port}")
        await server.start()
        await server.wait_for_termination()

    async def _generate(
        self, request: struct_pb2.Struct, context: grpc.aio.ServicerContext
    ) -> struct_pb2.Struct:
        payload = json_format.MessageToDict(request, preserving_proto_field_name=True)
        prompt = payload.get("prompt")
        if not isinstance(prompt, str) or not prompt:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("Field 'prompt' must be provided")
            return struct_pb2.Struct()

        try:
            generation_input = GenerationInput(
                prompt=prompt,
                endpoint=_optional_str(payload.get("endpoint")),
                model=_optional_str(payload.get("model")),
                parameters=_as_mapping(payload.get("parameters")),
                messages=_as_list_of_mappings(payload.get("messages")),
                metadata=_as_mapping(payload.get("metadata")),
            )
            result = await self._service.generate(generation_input)
        except RateLimitExceeded as exc:
            context.set_code(grpc.StatusCode.RESOURCE_EXHAUSTED)
            context.set_details(str(exc))
            return struct_pb2.Struct()
        except AdapterError as exc:
            context.set_code(grpc.StatusCode.FAILED_PRECONDITION)
            context.set_details(str(exc))
            return struct_pb2.Struct()

        return _result_to_struct(result)


def _as_mapping(value: Any) -> Optional[Dict[str, Any]]:
    if isinstance(value, dict):
        return value
    return None


def _as_list_of_mappings(value: Any) -> Optional[list[Dict[str, Any]]]:
    if isinstance(value, list):
        mapped: list[Dict[str, Any]] = []
        for item in value:
            if isinstance(item, dict):
                mapped.append(item)
        return mapped if mapped else None
    return None


def _optional_str(value: Any) -> Optional[str]:
    return str(value) if isinstance(value, str) and value else None


def _result_to_struct(result: GenerationResult) -> struct_pb2.Struct:
    payload: Dict[str, Any] = {
        "text": result.text,
        "endpoint": result.endpoint,
        "latency_ms": result.latency_ms,
        "raw": dict(result.raw),
    }
    if result.model is not None:
        payload["model"] = result.model
    if result.usage is not None:
        payload["usage"] = dict(result.usage)

    message = struct_pb2.Struct()
    json_format.ParseDict(payload, message, ignore_unknown_fields=True)
    return message


async def serve(config: AdapterConfig, host: str = "0.0.0.0", port: int = 50051) -> None:
    """Convenience helper to start a gRPC server from configuration."""

    service = LLMAdapterService(config)
    server = AdapterGrpcServer(service)
    try:
        await server.serve(host=host, port=port)
    finally:
        await service.aclose()


__all__ = ["AdapterGrpcServer", "serve"]
