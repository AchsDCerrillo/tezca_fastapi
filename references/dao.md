# DAO layer: `<feature>_dao.py`

The DAO **builds** SQLAlchemy statements and returns them. It never receives an `AsyncSession` and never awaits anything. The repository executes what the DAO builds.

The split has two benefits:
- Every query lives in one place per table, so it can be reviewed and unit-tested (compile the statement, assert the SQL) without a database.
- The repository can compose statements: add pagination, eager loading, or run several statements in one transaction.

## Template

```python
import uuid
from typing import Any

from sqlalchemy import Delete, Insert, Select, Update, delete, func, insert, or_, select, update
from sqlalchemy.orm import selectinload

from app.product.model.product_model_db import Product, ProductStatus


class ProductDao:
    """Builds SQLAlchemy statements for the products table. Never executes them."""

    def select_by_id(self, product_id: uuid.UUID, *, with_category: bool = False) -> Select[Product]:
        stmt = select(Product).where(Product.id == product_id)
        if with_category:
            stmt = stmt.options(selectinload(Product.category))
        return stmt

    def select_by_name(self, name: str) -> Select[Product]:
        return select(Product).where(Product.name == name)

    def select_all(
        self,
        *,
        status: ProductStatus | None = None,
        search: str | None = None,
        offset: int = 0,
        limit: int = 50,
    ) -> Select[Product]:
        stmt = self._apply_filters(select(Product), status=status, search=search)
        return stmt.order_by(Product.created_at.desc()).offset(offset).limit(limit)

    def count(self, *, status: ProductStatus | None = None, search: str | None = None) -> Select[int]:
        return self._apply_filters(select(func.count()).select_from(Product), status=status, search=search)

    def insert(self, values: dict[str, Any]) -> Insert:
        return insert(Product).values(**values).returning(Product)

    def update_by_id(self, product_id: uuid.UUID, values: dict[str, Any]) -> Update:
        return update(Product).where(Product.id == product_id).values(**values).returning(Product)

    def delete_by_id(self, product_id: uuid.UUID) -> Delete:
        return delete(Product).where(Product.id == product_id)

    def exists_by_name(self, name: str) -> Select[bool]:
        return select(select(Product.id).where(Product.name == name).exists())

    @staticmethod
    def _apply_filters[T](stmt: Select[T], *, status: ProductStatus | None, search: str | None) -> Select[T]:
        if status is not None:
            stmt = stmt.where(Product.status == status)
        if search:
            pattern = f"%{search}%"
            stmt = stmt.where(or_(Product.name.ilike(pattern), Product.description.ilike(pattern)))
        return stmt
```

## Rules
- **Inputs:** method arguments are plain values or `dict[str, Any]`, never Pydantic models. The DAO should not depend on the API shape; the repository converts with `body.model_dump(exclude_unset=True)`.
- **Return types:** return type-annotated statements: `Select[Model]` for one entity, `Select[int]` / `Select[bool]` for scalars, `Insert`, `Update`, `Delete`. This is SQLAlchemy 2.1 typing; `Select[tuple[Model]]` was the 2.0 form, and mypy rejects it on 2.1. Shared filter helpers are generic (`def _apply_filters[T](stmt: Select[T], ...) -> Select[T]`), so mypy keeps checking through them.
- **Naming:** `select_*` for reads, `count*`, `exists_*`, `insert`, `insert_many`, `update_*`, `delete_*`, `soft_delete_*`.
- **One DAO per table.** A feature with two tables gets two DAO classes; both may live in `<feature>_dao.py`.
- **RETURNING:** `insert(...).returning(Model)` and `update(...).returning(Model)` give the repository a fully loaded ORM object in a single round trip. Postgres, SQLite ≥ 3.35 and MariaDB support RETURNING. **MySQL does not.** On MySQL, return the statement without `.returning()` and let the repository re-select by id, or have the DAO expose `new(values) -> Model` so the repository can `session.add()` it. Check `DATABASE_DRIVER` in config before choosing.
- **Joins and eager loading:** add them to the statement here (`selectinload`, `joinedload`, `join`) behind keyword flags, so the repository decides what to load.
- **Raw SQL:** use `text()` only when the user explicitly asks for it, and always with bound parameters, never f-strings with user input.

## Quick unit test (optional, no database needed)
```python
from sqlalchemy.dialects import postgresql
stmt = ProductDao().select_by_id(some_uuid)
print(stmt.compile(dialect=postgresql.dialect()))
```
