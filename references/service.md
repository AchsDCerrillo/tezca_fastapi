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

- `Request` is `from fastapi import Request`, which is the incoming starlette request. It exposes `request.state` (request id, authenticated user set by middleware or dependencies), `request.headers` and `request.client`. Passing it everywhere keeps auth and tracing context available without changing signatures later.
- For endpoints without a body (GET/DELETE) that take filters, use a Pydantic **query model** (`ProductListQuery`). For a plain lookup by id, the path id is enough.
- Errors are raised as `HTTPException` from **starlette**, with status codes from `starlette.status`:

```python
from starlette import status
from starlette.exceptions import HTTPException

raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
```

## Template

```python
import logging
import uuid
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from starlette import status
from starlette.exceptions import HTTPException

from app.core.database import get_session
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
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Product name already exists")
        try:
            product = await self.product_repository.create(body.model_dump())
        except IntegrityError as exc:  # concurrent insert won the race on the unique constraint
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Product name already exists") from exc
        logger.info("product created id=%s", product.id)
        return ProductResponse.model_validate(product)

    async def get_product(self, request: Request, product_id: uuid.UUID) -> ProductResponse:
        product = await self.product_repository.get_by_id(product_id)
        if product is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
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
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Product name already exists")
        try:
            product = await self.product_repository.update(product_id, values)
        except IntegrityError as exc:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Product name already exists") from exc
        if product is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
        return ProductResponse.model_validate(product)

    async def delete_product(self, request: Request, product_id: uuid.UUID) -> None:
        if not await self.product_repository.delete(product_id):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")


def get_product_service(session: Annotated[AsyncSession, Depends(get_session)]) -> ProductService:
    return ProductService(product_repository=ProductRepository(session, ProductDao()))
```

## The factory (`get_<feature>_service`)
- It sits at the bottom of the service file and builds the whole object graph per request: session → DAO → datasource → repository → service.
- **Shared session:** every repository in one service must receive the **same** session (FastAPI caches `get_session` per request), so a multi-repository operation is one transaction.
- **Core clients:** inject them with their own dependency getters, e.g. `storage: Annotated[S3Storage, Depends(get_s3_storage)]`, and pass them to the datasource or service.
- **Services using another feature's repositories:** construct those repositories in this factory too. Import the other feature's repository and DAO here; the service class itself only sees repositories.

## Rules
- **Allowed dependencies:** repositories and core classes only. A service never imports a DAO or datasource *for use inside the class*. The factory imports the DAO only to construct the repository.
- **Return types:** always a Pydantic model (or `None` for 204). Map with `Model.model_validate(orm)`. Never return ORM objects to the router; serialization outside the session can trigger lazy loads that fail in async.
- **Error mapping:**

| Situation | Status |
|---|---|
| Not found | 404 |
| Duplicate/unique violation | 409. Check first for a clear message, **and** catch `sqlalchemy.exc.IntegrityError` around the write, because check-then-write races under concurrency. Apply this on create **and** on update when a unique field changes. |
| Business rule violated | 422 or 400 |
| Not authenticated | 401 |
| Forbidden | 403 |
| External provider failed (datasource exception) | 502/503 |

  Catch datasource and domain exceptions here and re-raise as `HTTPException(...) from exc`.
- **Missing methods:** if a needed repository method doesn't exist, create it (follow `repository.md`, and `dao.md` for any new statement) before writing the service method.
- **Empty scaffolds:** when the user asks only to scaffold a service, generate the class, the constructor and the factory, plus one method per agreed endpoint. Leave a body that raises `HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="Not implemented")`, so the route exists and is honest about it.
