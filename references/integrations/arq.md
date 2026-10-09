# Background job queue: ARQ (`app/core/jobs.py` + `worker.py`)

ARQ is an asyncio job queue on Redis, with retries, delays and cron. It suits this stack because jobs are plain `async def` functions that reuse services through `session_scope()` + `build_<feature>_service` (see `../background_jobs.md`).

**Requires Redis.** Run the Redis recipe (`redis.md`) first if `app/core/redis.py` / `REDIS_URL` don't exist.

**requirements.txt:** `arq==0.28.0`. Check for newer versions (`pip index versions arq`) and make sure it accepts the pinned `redis` major version; if pip reports a conflict, pin `redis` to what arq supports.

**Settings and `.env.example`:**
```python
# Jobs (ARQ)
jobs_queue_name: str = "arq:queue"
jobs_max_tries: int = 5
jobs_timeout_seconds: int = 300
```
```
JOBS_QUEUE_NAME=arq:queue
JOBS_MAX_TRIES=5
JOBS_TIMEOUT_SECONDS=300
```

## Enqueue side (`app/core/jobs.py`)
```python
from functools import lru_cache
from typing import Any

from arq import ArqRedis, create_pool
from arq.connections import RedisSettings

from app.core.config import get_settings

_pool: ArqRedis | None = None


@lru_cache
def redis_settings() -> RedisSettings:
    return RedisSettings.from_dsn(get_settings().redis_url)


async def get_job_queue() -> ArqRedis:
    """FastAPI dependency / plain getter."""
    global _pool
    if _pool is None:
        _pool = await create_pool(redis_settings(), default_queue_name=get_settings().jobs_queue_name)
    return _pool


async def enqueue(job_name: str, *args: Any, **kwargs: Any) -> str | None:
    job = await (await get_job_queue()).enqueue_job(job_name, *args, **kwargs)
    return job.job_id if job else None   # None = a job with the same _job_id is already queued


async def close_job_queue() -> None:
    global _pool
    if _pool is not None:
        await _pool.aclose()
        _pool = None
```
**Lifespan (`main.py`):** after `yield`, add `await close_job_queue()`.

**Enqueue from a service:** inject the queue through the service factory as a core class (`queue: Annotated[ArqRedis, Depends(get_job_queue)]`), or call `enqueue("reindex_product", str(product_id))`.
- Pass ids as strings, not ORM objects.
- Use `_job_id=f"reindex:{product_id}"` to de-duplicate jobs.
- Use `_defer_by=timedelta(...)` to delay a job.

## Worker side (`worker.py` at the project root)
```python
from typing import Any, ClassVar

from arq import cron

from app.core.config import get_settings
from app.core.database import close_db
from app.core.jobs import redis_settings
from app.core.logging import setup_logging
from app.product.product_jobs import archive_stale_products, reindex_product

settings = get_settings()


async def startup(ctx: dict[str, Any]) -> None:
    setup_logging()


async def shutdown(ctx: dict[str, Any]) -> None:
    await close_db()


class WorkerSettings:
    functions: ClassVar[list] = [reindex_product]
    cron_jobs: ClassVar[list] = [cron(archive_stale_products, hour={3}, minute={0})]
    redis_settings = redis_settings()
    queue_name = settings.jobs_queue_name
    max_tries = settings.jobs_max_tries
    job_timeout = settings.jobs_timeout_seconds
    on_startup = startup
    on_shutdown = shutdown
```
ARQ job functions receive `ctx` first:
```python
# app/product/product_jobs.py
async def reindex_product(ctx: dict, product_id: str) -> None:
    async with session_scope() as session:
        await build_product_service(session).reindex(None, uuid.UUID(product_id))
```
**Registering jobs:** when a feature adds a job, register it in `WorkerSettings.functions` (or `cron_jobs`).

**Run locally:** `arq worker.WorkerSettings`. Add a `make worker` target.

**docker-compose:** add a worker service to the same image:
```yaml
  worker:
    <<: *app
    command: ["arq", "worker.WorkerSettings"]
    restart: unless-stopped
    depends_on:
      redis:
        condition: service_healthy
      migrate:
        condition: service_completed_successfully
```
In production, run the worker as a separate service or task from the same image, with the same env vars.
