# Testing

Every feature ships with tests at three levels. Each level catches a different class of bug, and together they run in a few seconds.

| Level | File | Needs DB | Catches |
|---|---|---|---|
| DAO | `tests/<feature path>/test_<feature>_dao.py` | no | wrong filters, missing `where`, bad ordering/pagination |
| Service | `tests/<feature path>/test_<feature>_service.py` | no | business rules, error mapping (which exception for which case) |
| API | `tests/<feature path>/test_<feature>_api.py` | yes | wiring, validation, status codes, error body, real SQL, migrations |

`<feature path>` mirrors `app/`. For example, `app/project/api_key` → `tests/project/api_key/`. Add an empty `__init__.py` in each test folder so same-named modules in different features don't collide.

## The harness (created by start-fast-api)
- **`tests/conftest.py`:**
  - **Database:** uses `TEST_DATABASE_*` env vars (CI) or starts a throwaway Postgres with **testcontainers**.
  - **Schema:** runs `alembic upgrade head` once per test session, so migrations are tested on every run.
  - **`db_session` fixture:** an `AsyncSession` inside a transaction that is rolled back after each test, so tests never see each other's data.
  - **`client` fixture:** an `httpx.AsyncClient` over the app, with `get_session` overridden to use `db_session`. Each request commits or rolls back to a SAVEPOINT, just as production commits or rolls back per request.
- **`pyproject.toml`:** pytest-asyncio is in `auto` mode with a session event loop, so `async def test_...` just works. No decorator is needed.
- **Running tests:** `make test` / `pytest`. `TEST_SKIP_DB=1 pytest -m "not integration"` runs only the unit tests, without Docker.

## DAO tests (no database)

Compile the statement with the project's dialect and assert on the SQL. This is fast and catches most query mistakes.

```python
import uuid

from sqlalchemy.dialects import postgresql
from sqlalchemy.sql import Executable

from app.product.model.product_model_db import ProductStatus
from app.product.product_dao import ProductDao


def sql(stmt: Executable) -> str:
    # paramstyle="named": the default psycopg2 style would render LIKE patterns as '%%mug%%'
    return str(stmt.compile(dialect=postgresql.dialect(paramstyle="named"), compile_kwargs={"literal_binds": True}))


def test_select_all_filters_and_paginates() -> None:
    query = sql(ProductDao().select_all(status=ProductStatus.ACTIVE, search="mug", offset=20, limit=10))

    assert "products.status = 'active'" in query
    assert "ILIKE '%mug%'" in query
    assert "LIMIT 10 OFFSET 20" in query


def test_delete_by_id_targets_one_row() -> None:
    product_id = uuid.uuid4()
    assert f"WHERE products.id = '{product_id}'" in sql(ProductDao().delete_by_id(product_id))
```
Use `literal_binds` only in tests; it is how you see the real values. If a type can't be rendered literally (JSON, arrays), assert on `stmt.compile().params` instead.

## Service tests (no database)

Mock the repositories with `AsyncMock(spec=...)`. The `spec` makes the test fail if the service calls a method that doesn't exist. Assert on the returned model or on the **domain exception**.

```python
import uuid
from datetime import UTC, datetime
from decimal import Decimal
from types import SimpleNamespace
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest
from sqlalchemy.exc import IntegrityError

from app.core.exceptions import ConflictError, NotFoundError
from app.product.model.product_model_db import ProductStatus
from app.product.model.product_model_domain import ProductCreateRequest
from app.product.product_repository import ProductRepository
from app.product.product_service import ProductService

REQUEST = MagicMock()  # services only read request.state/headers


def product_row(**overrides: Any) -> SimpleNamespace:
    now = datetime.now(UTC)
    values = dict(id=uuid.uuid4(), name="Mug", description=None, price=Decimal("9.50"),
                  status=ProductStatus.ACTIVE, created_at=now, updated_at=now)
    return SimpleNamespace(**(values | overrides))


@pytest.fixture
def repo() -> AsyncMock:
    return AsyncMock(spec=ProductRepository)


async def test_create_rejects_duplicate_name(repo: AsyncMock) -> None:
    repo.exists_by_name.return_value = True

    with pytest.raises(ConflictError):
        await ProductService(repo).create_product(REQUEST, ProductCreateRequest(name="Mug", price=Decimal("9.50")))
    repo.create.assert_not_awaited()


async def test_create_maps_integrity_error_to_conflict(repo: AsyncMock) -> None:
    repo.exists_by_name.return_value = False
    repo.create.side_effect = IntegrityError("insert", {}, Exception("unique"))

    with pytest.raises(ConflictError):
        await ProductService(repo).create_product(REQUEST, ProductCreateRequest(name="Mug", price=Decimal("9.50")))


async def test_get_missing_product_raises_not_found(repo: AsyncMock) -> None:
    repo.get_by_id.return_value = None

    with pytest.raises(NotFoundError):
        await ProductService(repo).get_product(REQUEST, uuid.uuid4())
```
**What to cover:** one test per business rule and per error branch. A `SimpleNamespace` with the response fields is enough to stand in for an ORM row in `model_validate`, because the response models use `from_attributes=True`.

## API tests (real database)

```python
from typing import Any

import httpx
import pytest

pytestmark = pytest.mark.integration


async def create_product(client: httpx.AsyncClient, **overrides: Any) -> dict[str, Any]:
    payload = {"name": "Mug", "price": "9.50"} | overrides
    response = await client.post("/products", json=payload)
    assert response.status_code == 201, response.text
    return response.json()


async def test_create_and_get(client: httpx.AsyncClient) -> None:
    created = await create_product(client)

    response = await client.get(f"/products/{created['id']}")

    assert response.status_code == 200
    assert response.json()["name"] == "Mug"


async def test_duplicate_name_returns_conflict_body(client: httpx.AsyncClient) -> None:
    await create_product(client)

    response = await client.post("/products", json={"name": "Mug", "price": "1.00"})

    assert response.status_code == 409
    assert response.json()["code"] == "conflict"


async def test_validation_error_body(client: httpx.AsyncClient) -> None:
    response = await client.post("/products", json={"name": "", "price": "-1"})

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "validation_error"
    assert {tuple(e["loc"]) for e in body["errors"]} >= {("body", "name"), ("body", "price")}


async def test_list_paginates(client: httpx.AsyncClient) -> None:
    for i in range(3):
        await create_product(client, name=f"Mug {i}")

    body = (await client.get("/products", params={"limit": 2})).json()

    assert body["total"] == 3 and len(body["items"]) == 2
```
**Minimum per endpoint:** the happy path, plus each documented error status (404, 409, 422, 401/403 when auth applies). Build test data through the API or with small helper functions like `create_product`. Add a shared `tests/factories.py` only when several features need the same data.

**Auth-protected routes:** override the auth dependency in a fixture, e.g. `app.dependency_overrides[get_current_token] = lambda: TokenPayload(sub="user-1", ...)`, rather than minting real tokens in every test.

**External services:** never call real providers in tests. Override the core getter (`app.dependency_overrides[get_s3_storage] = lambda: fake_storage`), or use `httpx.MockTransport` for HTTP datasources.

## Non-Postgres projects
- **MySQL:** use `testcontainers.mysql.MySqlContainer("mysql:8.4")` and port 3306 in `conftest.py`.
- **SQLite:**
  - Skip testcontainers; point `DATABASE_NAME` at a temp file in `pytest_configure`.
  - `join_transaction_mode="create_savepoint"` works with aiosqlite, but SQLite has no RETURNING before 3.35 and doesn't enforce types. Keep at least the CI run on the production database engine.
