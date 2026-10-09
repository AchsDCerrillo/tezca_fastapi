# Shared HTTP client (`app/core/http_client.py`)

Every datasource that calls a third-party REST API uses **one** shared `httpx.AsyncClient`. Connection pooling and keep-alive only work if the client is reused. A client created per request leaks sockets and adds TLS handshakes to every call.

**requirements.txt:** `httpx==0.28.1`

**Settings and `.env.example`:**
```python
# Outbound HTTP
http_timeout_seconds: float = 10.0
http_max_connections: int = 100
```
```
HTTP_TIMEOUT_SECONDS=10
HTTP_MAX_CONNECTIONS=100
```

**Module:**
```python
import httpx

from app.core.config import get_settings

_client: httpx.AsyncClient | None = None


def get_http_client() -> httpx.AsyncClient:
    """FastAPI dependency / plain getter. Created lazily, closed in the app lifespan."""
    global _client
    if _client is None:
        settings = get_settings()
        _client = httpx.AsyncClient(
            timeout=settings.http_timeout_seconds,
            limits=httpx.Limits(max_connections=settings.http_max_connections),
            headers={"User-Agent": f"{settings.app_name}/{settings.app_version}"},
        )
    return _client


async def close_http_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
```

**Lifespan (`main.py`):** after `yield`, add `await close_http_client()`.

**Usage in a service factory:**
```python
def get_order_service(
    session: Annotated[AsyncSession, Depends(get_session)],
    http: Annotated[httpx.AsyncClient, Depends(get_http_client)],
) -> OrderService:
    repo = OrderRepository(session, OrderDao(), ShippingDatasource(http, get_settings()))
    return OrderService(order_repository=repo)
```
For a provider that needs its own base URL, auth header or retries, the datasource passes those on each call. Alternatively, add a second named client here (e.g. `get_shipping_http_client`) with `base_url=` set.
