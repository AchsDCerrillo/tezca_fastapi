# Datasource layer: `<feature>_datasource.py` (optional)

A datasource reads and writes data that is **not** in our SQL database: object storage, a cache, a payment provider, an external REST API, a message queue. A feature only has one when it needs one.

The datasource adapts a generic core client (e.g. `S3Storage`) to what this feature needs (e.g. "upload a product image under `products/<id>/`"). The repository can then combine it with database work without knowing the client's details.

## Template: wrapping a core client

```python
import uuid

from app.core.s3 import S3Storage


class ProductDatasource:
    def __init__(self, storage: S3Storage):
        self.storage = storage

    async def upload_image(self, product_id: uuid.UUID, data: bytes, content_type: str) -> str:
        key = f"products/{product_id}/image"
        await self.storage.upload_bytes(key, data, content_type=content_type)
        return key

    async def image_url(self, key: str, expires_in: int = 3600) -> str:
        return await self.storage.presigned_get_url(key, expires_in=expires_in)
```

## Template: third-party REST API

```python
import logging
from typing import Any

import httpx

from app.core.config import Settings
from app.core.exceptions import ExternalServiceError

logger = logging.getLogger(__name__)


class ShippingRateError(ExternalServiceError):
    """The shipping provider failed or returned something unusable (-> 502 with code shipping_unavailable)."""

    code = "shipping_unavailable"
    message = "Shipping provider unavailable"


class ShippingDatasource:
    def __init__(self, http: httpx.AsyncClient, settings: Settings):
        self.http = http
        self.base_url = settings.shipping_api_url
        self.api_key = settings.shipping_api_key

    async def get_rates(self, origin_zip: str, dest_zip: str, weight_kg: float) -> list[dict[str, Any]]:
        try:
            response = await self.http.post(
                f"{self.base_url}/rates",
                json={"from": origin_zip, "to": dest_zip, "weight": weight_kg},
                headers={"Authorization": f"Bearer {self.api_key}"},
                timeout=10,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            logger.warning("shipping rates request failed: %s", exc)
            raise ShippingRateError() from exc
        return response.json()["rates"]
```

## Rules
- **Wiring:** receive clients through the constructor. Shared clients come from `app/core` (`get_http_client()`, `get_s3_storage()`, `get_redis()`); never create a new `httpx.AsyncClient` or boto session per call, because connection pools are expensive.
- **Configuration:** URLs, keys and bucket names come from `Settings` (add them to `config.py` and `.env.example`). Never hardcode them.
- **Return values:** return plain Python data (dicts, dataclasses, primitives, or small Pydantic models that describe the *external* payload). Never return SQLAlchemy models; the datasource does not know our database.
- **Errors:** raise a small, named exception that **subclasses `ExternalServiceError`** (from `app/core/exceptions.py`), like `ShippingRateError`, instead of leaking `httpx`/`botocore` errors. It reaches the client as a 502 with its own `code` without the service having to map it. The service may still catch it to add a fallback.
- **Missing core client:** if the needed client doesn't exist in `app/core`, create it with the **add-core** workflow first; the datasource then wraps it.
- **Where it's used:** only the repository uses the datasource. The service never imports a datasource directly.
