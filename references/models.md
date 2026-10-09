# Models: `<feature>_model_db.py` and `<feature>_model_domain.py`

Each feature's `model/` folder holds two files:
- `<feature>_model_db.py` contains the SQLAlchemy tables, which are the shape of the database.
- `<feature>_model_domain.py` contains the Pydantic models, which are the shape of the API.

They are separate on purpose. You can change the API without a migration, and add a column without leaking it to clients.

## Base and mixins (live in `app/core/models.py`)

```python
from app.core.models import Base, UUIDPkMixin, TimestampMixin
```

- `Base` carries a MetaData `naming_convention`. Alembic then generates stable, predictable constraint names, which matters when you later drop or alter a constraint.
- `UUIDPkMixin` gives `id: Mapped[uuid.UUID]` with a Python-side `uuid4` default. The default is Python-side so it works on every database, not only Postgres.
- `TimestampMixin` gives `created_at` / `updated_at` (timezone-aware, server defaults).

Use them unless the user asks for something different, such as integer ids or no timestamps.

## `<feature>_model_db.py`

```python
import enum
import uuid
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import Enum as SAEnum
from sqlalchemy import ForeignKey, Index, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.models import Base, TimestampMixin, UUIDPkMixin

if TYPE_CHECKING:
    from app.category.model.category_model_db import Category


class ProductStatus(enum.Enum):
    ACTIVE = "active"
    ARCHIVED = "archived"


class Product(UUIDPkMixin, TimestampMixin, Base):
    __tablename__ = "products"
    __table_args__ = (Index("ix_products_category_id_status", "category_id", "status"),)

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[ProductStatus] = mapped_column(
        SAEnum(ProductStatus, name="product_status", values_callable=lambda e: [m.value for m in e]),
        default=ProductStatus.ACTIVE,
        nullable=False,
    )

    # Relationships
    category_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("categories.id", ondelete="CASCADE"), index=True)
    category: Mapped["Category"] = relationship(back_populates="products")

    def __repr__(self) -> str:
        return f"Product(id={self.id!r}, name={self.name!r})"
```

### Rules and gotchas
- **Enums:** always pass `values_callable=lambda e: [m.value for m in e]`. Without it SQLAlchemy stores the member *name* (`ACTIVE`) instead of the value (`active`). That silently breaks any SQL, report or other service that expects the value.
- **Postgres enum types:** Alembic autogenerate creates them, but it does **not** drop them on downgrade. Add `sa.Enum(name="product_status").drop(op.get_bind(), checkfirst=True)` to `downgrade()`. Adding a value to an existing enum needs a manual `op.execute("ALTER TYPE product_status ADD VALUE 'draft'")`.
- **Defaults:** `default=` is applied by SQLAlchemy (Python side) only. If rows may be inserted outside the app (SQL scripts, other services), also set `server_default=` (e.g. `server_default="active"` for an enum, `server_default=sa.false()` for booleans) so the database enforces it. Ask the user when they say "default X".
- **Nullable:** `Mapped[str | None]` means nullable, `Mapped[str]` means NOT NULL. Be explicit with `nullable=` when it helps readability.
- **Foreign keys:** reference `"<table>.<column>"` and choose `ondelete` consciously; ask the user if it's unclear. Index FK columns.
- **Cross-feature relationships:** import the other model only under `TYPE_CHECKING` and use string annotations, which avoids import cycles. Both models must be imported in `app/core/model_registry.py` so the mapper can resolve them.
- **Postgres-only types** (`JSONB`, `ARRAY`, `INET`) come from `sqlalchemy.dialects.postgresql`. Only use them when the project's database is Postgres; check `DATABASE_DRIVER` in `app/core/config.py`.
- **Money:** use `Numeric`, never `Float`.
- **Several tables in one feature:** they may share one `<feature>_model_db.py`. If the file grows past roughly 300 lines, split it into `<entity>_model_db.py` files inside the same `model/` folder.

### `model/__init__.py`
Re-export the public names:
```python
from app.product.model.product_model_db import Product, ProductStatus
from app.product.model.product_model_domain import (
    ProductCreateRequest,
    ProductResponse,
    ProductUpdateRequest,
)

__all__ = ["Product", "ProductStatus", "ProductCreateRequest", "ProductUpdateRequest", "ProductResponse"]
```

### Register the model
Add `import app.<feature>.model.<feature>_model_db  # noqa: F401` to `app/core/model_registry.py`. Alembic autogenerate only sees tables whose modules are imported, so a forgotten line here means an empty migration.

## `<feature>_model_domain.py`

```python
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.product.model.product_model_db import ProductStatus


class ProductCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = None
    price: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    category_id: uuid.UUID


class ProductUpdateRequest(BaseModel):
    """PATCH semantics: only the fields that were sent are applied (use model_dump(exclude_unset=True))."""
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = None
    price: Decimal | None = Field(default=None, gt=0, max_digits=12, decimal_places=2)
    status: ProductStatus | None = None

    @field_validator("name", "price", "status")
    @classmethod
    def not_null(cls, value: Any) -> Any:
        # Omitted field = "don't change it"; an explicit null on a NOT NULL column is a 422, not a DB 500.
        if value is None:
            raise ValueError("may not be null")
        return value


class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    description: str | None
    price: Decimal
    status: ProductStatus
    category_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


class ProductListQuery(BaseModel):
    """Query-string filters for GET /products (router declares it with Annotated[..., Query()])."""
    status: ProductStatus | None = None
    search: str | None = Field(default=None, max_length=100)
    offset: int = Field(default=0, ge=0)
    limit: int = Field(default=50, ge=1, le=200)


class ProductListResponse(BaseModel):
    items: list[ProductResponse]
    total: int
    offset: int
    limit: int
```

### Rules
- Responses use `ConfigDict(from_attributes=True)`, so the service can call `ProductResponse.model_validate(orm_obj)`.
- Never expose secrets or internal columns (password hashes, api key hashes, soft-delete flags) in a `*Response`.
- Validation constraints belong in `Field(...)`: lengths, ranges, `EmailStr` (needs `email-validator`), regex `pattern=`.
- A `*Response` that nests a relationship (e.g. `category: CategoryResponse`) requires the repository to eager-load it (`selectinload`). An async session cannot lazy-load during serialization; it raises `MissingGreenlet`.
- Reuse the db enum in domain models instead of redefining it.
- **UpdateRequest validation:** constraints must match CreateRequest, field by field. Add a `not_null` validator listing every field whose column is NOT NULL. It only fires on an explicit `null`, because omitted fields keep their default and aren't validated.
