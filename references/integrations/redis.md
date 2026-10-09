# Redis (`app/core/redis.py`)

**requirements.txt:** `redis==8.1.0`. It includes `redis.asyncio`; add `hiredis` for speed if wanted.

**Settings and `.env.example`:**
```python
# Redis
redis_url: str = "redis://localhost:6379/0"
redis_default_ttl: int = 300
```
```
REDIS_URL=redis://localhost:6379/0
REDIS_DEFAULT_TTL=300
```
`.env.*` files hold host-friendly values (`localhost`). Inside compose, the hostname is the service name, so add the override under `x-app.environment` in `docker-compose.yml`:
```yaml
    REDIS_URL: redis://redis:6379/0
```

**Class:**
```python
import json
import logging
from functools import lru_cache
from typing import Any

from redis.asyncio import Redis
from redis.asyncio.lock import Lock

from app.core.config import get_settings

logger = logging.getLogger(__name__)


class RedisClient:
    """Thin async wrapper: JSON cache helpers + access to the raw client for anything else."""

    def __init__(self, url: str, default_ttl: int = 300):
        self.raw: Redis = Redis.from_url(url, decode_responses=True)
        self.default_ttl = default_ttl

    async def get_json(self, key: str) -> Any | None:
        value = await self.raw.get(key)
        return json.loads(value) if value is not None else None

    async def set_json(self, key: str, value: Any, ttl: int | None = None) -> None:
        await self.raw.set(key, json.dumps(value, default=str), ex=ttl or self.default_ttl)

    async def delete(self, *keys: str) -> int:
        return await self.raw.delete(*keys) if keys else 0

    async def incr(self, key: str, ttl: int | None = None) -> int:
        """Counter with expiry on first increment (rate limiting)."""
        value = await self.raw.incr(key)
        if value == 1 and ttl:
            await self.raw.expire(key, ttl)
        return value

    def lock(self, name: str, timeout: float = 10) -> Lock:
        return self.raw.lock(name, timeout=timeout)

    async def ping(self) -> bool:
        return await self.raw.ping()

    async def close(self) -> None:
        await self.raw.aclose()


@lru_cache
def get_redis() -> RedisClient:
    settings = get_settings()
    return RedisClient(settings.redis_url, settings.redis_default_ttl)
```

**Lifespan (`main.py`):** close the pool on shutdown:
```python
from app.core.redis import get_redis
...
    yield
    await get_redis().close()
```

**docker-compose:**
```yaml
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]   # change the host side if 6379 is already in use (lsof -i :6379)
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 5
```
Add `redis: {condition: service_healthy}` to the api's `depends_on`.
