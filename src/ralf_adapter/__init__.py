"""REST and gRPC adapter bridging R.A.L.F. with external LLM endpoints."""

from .config import AdapterConfig
from .grpc_server import AdapterGrpcServer, serve
from .rest import create_app
from .service import GenerationInput, GenerationResult, LLMAdapterService

__all__ = [
    "AdapterConfig",
    "AdapterGrpcServer",
    "create_app",
    "GenerationInput",
    "GenerationResult",
    "LLMAdapterService",
    "serve",
]
