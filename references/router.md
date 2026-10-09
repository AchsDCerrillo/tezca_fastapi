# Router layer: `<feature>_router.py` and `app/app_router.py`

The router only maps HTTP to the service. It holds no logic, no repository and no session handling. If you are tempted to put an `if` in a route, it belongs in the service.

## Template

```python
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request
from starlette import status

from app.product.model.product_model_domain import (
    ProductCreateRequest,
    ProductListQuery,
    ProductListResponse,
    ProductResponse,
    ProductUpdateRequest,
)
from app.product.product_service import ProductService, get_product_service

router = APIRouter(prefix="/products", tags=["products"])

ProductServiceDep = Annotated[ProductService, Depends(get_product_service)]


@router.post("", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
async def create_product(request: Request, body: ProductCreateRequest, service: ProductServiceDep) -> ProductResponse:
    return await service.create_product(request, body)


@router.get("", response_model=ProductListResponse)
async def list_products(
    request: Request, query: Annotated[ProductListQuery, Query()], service: ProductServiceDep
) -> ProductListResponse:
    return await service.list_products(request, query)


@router.get("/{product_id}", response_model=ProductResponse)
async def get_product(request: Request, product_id: uuid.UUID, service: ProductServiceDep) -> ProductResponse:
    return await service.get_product(request, product_id)


@router.patch("/{product_id}", response_model=ProductResponse)
async def update_product(
    request: Request, product_id: uuid.UUID, body: ProductUpdateRequest, service: ProductServiceDep
) -> ProductResponse:
    return await service.update_product(request, product_id, body)


@router.delete("/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_product(request: Request, product_id: uuid.UUID, service: ProductServiceDep) -> None:
    await service.delete_product(request, product_id)
```

## Rules
- **Router module:** the module-level variable is always named `router`.
- **Prefix and tags:** `prefix` is the resource path (plural, kebab-case for multiword: `/api-keys`). `tags` is a readable group name.
- **Endpoints:** each endpoint calls exactly **one** service method and returns its result. Set `response_model` and an explicit `status_code` for non-200 responses (201 create, 204 delete).
- **Path ids:** type them with the real id type (`uuid.UUID` if the model uses UUID). Don't use `int` for UUID keys.
- **Query models:** declare filters with `Annotated[ProductListQuery, Query()]`, a Pydantic model whose fields become query parameters.
- **Auth:** protection is a dependency, e.g. `user: Annotated[CurrentUser, Depends(get_current_user)]` from `app/core/security.py` or the router-level `dependencies=[...]`. Pass the user to the service via `request.state` or as an argument, whichever the user prefers.
- **Duplicate names:** don't define two functions with the same name in one router file (FastAPI keeps both routes, but the second silently shadows the first in the module, and it confuses OpenAPI operation ids).

## Registering in `app/app_router.py`

`app/app_router.py` is the single place where feature routers are mounted. `main.py` includes only this router.

```python
from fastapi import APIRouter

from app.product.product_router import router as product_router
from app.project.api_key.api_key_router import router as api_key_router

router = APIRouter()

router.include_router(product_router)
router.include_router(api_key_router, prefix="/projects/{project_id}")
```

- Keep the imports sorted and add one `include_router` line per feature.
- **Nested resources:** either give the child router the full prefix in its own file, or pass the parent segment here with `prefix=`. Ask the user which URL they want, and keep it consistent with the existing routers.
- **Global prefix:** if the project uses one (e.g. `/api/v1`), it is set where `main.py` includes `app_router`, not per feature.
