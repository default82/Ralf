"""Simple asynchronous token bucket rate limiter."""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass


@dataclass(slots=True)
class RateLimiter:
    """Token bucket limiter that works with asyncio coroutines."""

    capacity: int
    refill_seconds: float

    def __post_init__(self) -> None:
        self._tokens = float(self.capacity)
        self._updated = time.monotonic()
        self._lock = asyncio.Lock()

    @classmethod
    def per_minute(cls, requests_per_minute: int) -> "RateLimiter":
        return cls(capacity=requests_per_minute, refill_seconds=60.0 / max(requests_per_minute, 1))

    async def acquire(self, tokens: float = 1.0) -> None:
        async with self._lock:
            await self._wait_for_tokens(tokens)
            self._tokens -= tokens

    async def try_acquire(self, tokens: float = 1.0) -> bool:
        async with self._lock:
            self._refill()
            if self._tokens >= tokens:
                self._tokens -= tokens
                return True
            return False

    async def _wait_for_tokens(self, tokens: float) -> None:
        while True:
            self._refill()
            if self._tokens >= tokens:
                return
            missing = tokens - self._tokens
            await asyncio.sleep(missing * self.refill_seconds)

    def _refill(self) -> None:
        now = time.monotonic()
        delta = now - self._updated
        if delta <= 0:
            return
        self._tokens = min(self.capacity, self._tokens + delta / self.refill_seconds)
        self._updated = now


__all__ = ["RateLimiter"]
