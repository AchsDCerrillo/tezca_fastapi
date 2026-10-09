# Work outside HTTP: background jobs, scheduled tasks, scripts

The business logic lives in services, and services are built by the plain factory `build_<feature>_service(session)`. Anything that isn't an HTTP request reuses them through the same path:

```python
from app.core.database import session_scope
from app.product.product_service import build_product_service

async with session_scope() as session:          # one unit of work: commit on success, rollback on error
    service = build_product_service(session)
    await service.archive_stale_products(None, days=90)
```

`session_scope()` (in `app/core/database.py`) is the non-HTTP twin of `get_session`. Never reuse a request's session in work that outlives the request: the session closes when the response is sent.

## Choosing the mechanism

| Need | Use |
|---|---|
| Small fire-and-forget work after the response, where losing it on restart is fine (send a welcome email, warm a cache) | FastAPI `BackgroundTasks` |
| Retries, scheduling/cron, work that must survive restarts, heavy jobs, more than one process | A job queue: **ARQ** (async, Redis-based) via `add-core` → `integrations/arq.md` |
| One-off maintenance, data fixes | A script in `scripts/` that uses `session_scope()` |

### FastAPI BackgroundTasks
The route schedules a function; that function opens its **own** `session_scope()`:

```python
# product_router.py
@router.post("/{product_id}/reindex", status_code=status.HTTP_202_ACCEPTED)
async def reindex_product(product_id: uuid.UUID, background: BackgroundTasks) -> None:
    background.add_task(reindex_product_job, product_id)

# product_jobs.py (in the feature folder)
async def reindex_product_job(product_id: uuid.UUID) -> None:
    async with session_scope() as session:
        await build_product_service(session).reindex(None, product_id)
```

### Job functions
- Put a feature's job functions in `app/<feature>/<feature>_jobs.py`.
- Each job takes **plain, serializable arguments** (ids, not ORM objects), opens `session_scope()`, builds the service with `build_<feature>_service`, and calls one service method. That keeps all logic in the service, where it is tested.
- **Service methods called from jobs:** they take `request: Request | None = None`, since there is no HTTP request. They must not depend on `request` being present; pass needed context (user id, tenant) as explicit arguments instead.
- **Errors:** domain exceptions raised inside a job are logged by the worker and, with ARQ, retried according to the job's settings. Decide per job whether a `NotFoundError` should retry (usually not; just log and return).
- **Idempotency:** jobs may run twice (retries, redeploys). Make them idempotent by checking state before acting.

### Scripts
- Scripts call a **service method**, never a repository directly, so the rules and logging stay in one place.
- If no method fits, add one through the `work-service` workflow, e.g. `async def count_products(self, request: Request | None = None, *, status: ProductStatus | None = None) -> int`, with a unit test.
```python
# scripts/backfill_slugs.py  -> python -m scripts.backfill_slugs
import asyncio

from app.core.database import session_scope
from app.core.logging import setup_logging
from app.product.product_service import build_product_service


async def main() -> None:
    setup_logging()
    async with session_scope() as session:
        await build_product_service(session).backfill_slugs(None)


if __name__ == "__main__":
    asyncio.run(main())
```
