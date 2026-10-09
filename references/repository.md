# Repository layer: `<feature>_repository.py`

The repository is where database operations actually happen. It:
- executes the statements the DAO builds;
- combines them with datasource calls into whole operations (e.g. "create the product row and upload its image");
- returns **SQLAlchemy model instances** (or `None`, lists, counts, booleans).

## Template

```python
import uuid
from collections.abc import Sequence
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.product.model.product_model_db import Product, ProductStatus
from app.product.product_dao import ProductDao
from app.product.product_datasource import ProductDatasource  # only if the feature has one


class ProductRepository:
    def __init__(self, session: AsyncSession, dao: ProductDao, datasource: ProductDatasource | None = None):
        self.session = session
        self.dao = dao
        self.datasource = datasource

    async def get_by_id(self, product_id: uuid.UUID, *, with_category: bool = False) -> Product | None:
        result = await self.session.scalars(self.dao.select_by_id(product_id, with_category=with_category))
        return result.one_or_none()

    async def get_by_name(self, name: str) -> Product | None:
        result = await self.session.scalars(self.dao.select_by_name(name))
        return result.one_or_none()

    async def get_all(
        self, *, status: ProductStatus | None = None, search: str | None = None, offset: int = 0, limit: int = 50
    ) -> Sequence[Product]:
        result = await self.session.scalars(
            self.dao.select_all(status=status, search=search, offset=offset, limit=limit)
        )
        return result.all()

    async def count(self, *, status: ProductStatus | None = None, search: str | None = None) -> int:
        return await self.session.scalar(self.dao.count(status=status, search=search)) or 0

    async def create(self, values: dict[str, Any]) -> Product:
        result = await self.session.scalars(self.dao.insert(values))
        return result.one()

    async def update(self, product_id: uuid.UUID, values: dict[str, Any]) -> Product | None:
        if not values:
            return await self.get_by_id(product_id)
        result = await self.session.scalars(
            self.dao.update_by_id(product_id, values),
            execution_options={"synchronize_session": False},
        )
        return result.one_or_none()

    async def delete(self, product_id: uuid.UUID) -> bool:
        result = await self.session.execute(self.dao.delete_by_id(product_id))
        return result.rowcount > 0

    async def exists_by_name(self, name: str) -> bool:
        return bool(await self.session.scalar(self.dao.exists_by_name(name)))

    # Example of a whole operation combining dao + datasource
    async def create_with_image(self, values: dict[str, Any], image: bytes, content_type: str) -> Product:
        product = await self.create(values)
        key = await self.datasource.upload_image(product.id, image, content_type)
        return await self.update(product.id, {"image_key": key})
```

## Rules
- **Session:** the repository receives the `AsyncSession` and the DAO (and the datasource / core clients if needed) through its constructor. The service factory wires them (see `service.md`).
- **Commits:** never `commit()`. `get_session` in `app/core/database.py` commits when the request succeeds and rolls back on any exception, so one HTTP request equals one transaction, no matter how many repositories the service touches. Use `await self.session.flush()` when you need generated values mid-operation.
- **Errors:** don't raise HTTP errors here. Report "not found" with `None` / `False`; the service decides what that means for the client. Let database exceptions (e.g. `IntegrityError`) propagate, or translate them into a small domain exception if the user wants that, and let the service map it to an HTTP status.
- **Inputs:** plain values or `dict[str, Any]`. The service converts Pydantic with `body.model_dump(exclude_unset=True)`.
- **Direct core calls:** core classes (e.g. `RedisClient` for caching) may be called directly from the repository when wrapping them in a datasource would add nothing.
- **Missing DAO statements:** if a method needs a statement the DAO doesn't have, add it to the DAO first (follow `dao.md`). Don't build statements inline in the repository; keeping them in the DAO is what makes queries reviewable.
- **Bulk operations:** `await self.session.execute(insert(Model), list_of_dicts)` (ORM bulk insert) via a DAO `insert_many()` that returns `insert(Model)`.
- **MySQL (no RETURNING):** execute the insert, then re-select by the id you generated in Python (`values["id"] = uuid.uuid4()`).
