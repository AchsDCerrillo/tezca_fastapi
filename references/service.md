# Service layer: `<feature>_service.py`

The service holds the business logic. It:
- receives the HTTP `Request` and validated Pydantic input;
- orchestrates one or more repositories and core classes;
- enforces rules ("name must be unique", "only the owner can edit");
- returns **Pydantic response models** ready for the client.

## Method signature (project convention)

Every public service method takes `request: Request` first, then the Pydantic request model for that operation, then any path identifiers:

```python
async def create_product(self, request: Request, body: ProductCreateRequest) -> ProductResponse
async def update_product(self, request: Request, product_id: uuid.UUID, body: ProductUpdateRequest) -> ProductResponse
async def list_products(self, request: Request, query: ProductListQuery) -> ProductListResponse
async def get_product(self, request: Request, product_id: uuid.UUID) -> ProductResponse
```

- `Request` is `from fastapi import Request`, which is the incoming starlette request. It exposes `request.state` (request id, authenticated user set by middleware or dependencies), `request.headers` and `request.client`. Use it only to *read* context; never build responses from it.
- For endpoints without a body (GET/DELETE) that take filters, use a Pydantic **query model** (`ProductListQuery`). For a plain lookup by id, the path id is enough.
- Methods that background jobs also call (see `background_jobs.md`) may take `request: Request | None = None`.

## Errors: raise domain exceptions, not HTTP exceptions

Services raise the exceptions in `app/core/exceptions.py`. The handlers in `app/core/error_handlers.py` turn them into the standard error body, `{"detail", "code", "request_id", "errors"?}`, with the right status. Business logic therefore never imports Starlette/HTTP types, and the same service works from a route, a CLI command or a background worker.

```python
from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError

raise NotFoundError("Product not found")                         # 404, code "not_found"
raise ConflictError("Product name already exists")               # 409, code "conflict"
raise BusinessRuleError("Cannot archive a product with open orders", code="product_has_open_orders")  # 422
```

| Situation | Exception | Status |
|---|---|---|
| Not found | `NotFoundError` | 404 |
| Duplicate / unique violation | `ConflictError` | 409 |
| Business rule violated | `BusinessRuleError` (custom `code=` per rule) | 422 |
| Malformed input that Pydantic couldn't catch | `BadRequestError` | 400 |
| Not authenticated | `UnauthorizedError` | 401 |
| Not allowed | `ForbiddenError` | 403 |
| Provider failed (datasource/core) | `ExternalServiceError` (datasource errors subclass it) | 502 |

- **Duplicates:** check first for a clear message, **and** catch `sqlalchemy.exc.IntegrityError` around the write, because check-then-write races under concurrency. Apply this on create, and on update when a unique field changes.
- **Machine-readable codes:** give business rules a specific `code=` (`"insufficient_stock"`); clients switch on `code`, humans read `detail`.
- **New exception types:** for a recurring case, subclass `AppError` in `app/core/exceptions.py`, with its own `status_code`, `code` and `message`.
- **`HTTPException`** is fine in routers and HTTP-only dependencies, which are the HTTP edge. The handler formats it with the same body.

## Template

```python
import logging
import uuid
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.exceptions import ConflictError, NotFoundError
from app.product.model.product_model_domain import (
    ProductCreateRequest,
    ProductListQuery,
    ProductListResponse,
    ProductResponse,
    ProductUpdateRequest,
)
from app.product.product_dao import ProductDao
from app.product.product_repository import ProductRepository

logger = logging.getLogger(__name__)


class ProductService:
    def __init__(self, product_repository: ProductRepository):
        self.product_repository = product_repository

    async def create_product(self, request: Request, body: ProductCreateRequest) -> ProductResponse:
        if await self.product_repository.exists_by_name(body.name):
            raise ConflictError("Product name already exists")
        try:
            product = await self.product_repository.create(body.model_dump())
        except IntegrityError as exc:  # a concurrent insert won the race on the unique constraint
            raise ConflictError("Product name already exists") from exc
        logger.info("product created id=%s", product.id)
        return ProductResponse.model_validate(product)

    async def get_product(self, request: Request, product_id: uuid.UUID) -> ProductResponse:
        product = await self.product_repository.get_by_id(product_id)
        if product is None:
            raise NotFoundError("Product not found")
        return ProductResponse.model_validate(product)

    async def list_products(self, request: Request, query: ProductListQuery) -> ProductListResponse:
        filters = query.model_dump(exclude={"offset", "limit"})
        items = await self.product_repository.get_all(**filters, offset=query.offset, limit=query.limit)
        total = await self.product_repository.count(**filters)
        return ProductListResponse(
            items=[ProductResponse.model_validate(p) for p in items],
            total=total,
            offset=query.offset,
            limit=query.limit,
        )

    async def update_product(
        self, request: Request, product_id: uuid.UUID, body: ProductUpdateRequest
    ) -> ProductResponse:
        values = body.model_dump(exclude_unset=True)
        if "name" in values:
            existing = await self.product_repository.get_by_name(values["name"])
            if existing is not None and existing.id != product_id:
                raise ConflictError("Product name already exists")
        try:
            product = await self.product_repository.update(product_id, values)
        except IntegrityError as exc:
            raise ConflictError("Product name already exists") from exc
        if product is None:
            raise NotFoundError("Product not found")
        return ProductResponse.model_validate(product)

    async def delete_product(self, request: Request, product_id: uuid.UUID) -> None:
        if not await self.product_repository.delete(product_id):
            raise NotFoundError("Product not found")


def build_product_service(session: AsyncSession) -> ProductService:
    """Plain factory: usable from routes (below), background jobs and scripts (with session_scope())."""
    return ProductService(product_repository=ProductRepository(session, ProductDao()))


def get_product_service(session: Annotated[AsyncSession, Depends(get_session)]) -> ProductService:
    return build_product_service(session)
```

## The two factories
- **`build_<feature>_service(session, ...)`** is a plain function. It builds the whole object graph: DAO → datasource → repository → service.
  - Every repository receives the **same** session, so a multi-repository operation is one transaction.
  - Other features' repositories are built here too.
  - Core clients are passed in as parameters, or taken from their cached getters (`get_s3_storage()`).
- **`get_<feature>_service(...)`** is the FastAPI dependency. It only resolves `Depends(...)` (session, `get_http_client`, …) and calls `build_<feature>_service`.

  Background jobs and scripts call the plain factory with `async with session_scope() as session:` (see `background_jobs.md`). That way the business logic has one wiring path, not two.

## Rules
- **Allowed dependencies:** repositories and core classes only. A service never uses a DAO or datasource *inside the class*. The factories import the DAO only to construct the repository.
- **Return types:** always a Pydantic model (or `None` for 204). Map with `Model.model_validate(orm)`. Never return ORM objects to the router; serialization outside the session can trigger lazy loads that fail in async.
- **External failures:** let datasource exceptions (subclasses of `ExternalServiceError`) propagate, or catch them to add context or a fallback.
- **Missing methods:** if a needed repository method doesn't exist, create it (follow `repository.md`, and `dao.md` for any new statement) before writing the service method.
- **Empty scaffolds:** when the user asks only to scaffold a service, generate the class and factories plus one method per agreed endpoint. Make each body `raise NotImplementedAppError()` (501), so the route exists and is honest about it.
- **Tests:** every service method gets tests (see `testing.md`): a unit test with mocked repositories for each rule and error, plus API tests for the happy path.
