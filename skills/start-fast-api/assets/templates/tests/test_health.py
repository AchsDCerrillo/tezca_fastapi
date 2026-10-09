import httpx
import pytest

pytestmark = pytest.mark.integration


async def test_health(client: httpx.AsyncClient) -> None:
    response = await client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert "X-Request-ID" in response.headers


async def test_unknown_route_uses_standard_error_body(client: httpx.AsyncClient) -> None:
    response = await client.get("/this-route-does-not-exist")

    assert response.status_code == 404
    body = response.json()
    assert body["code"] == "not_found"
    assert body["request_id"] == response.headers["X-Request-ID"]


async def test_unhandled_error_returns_standard_500(client: httpx.AsyncClient) -> None:
    from main import app

    async def boom() -> None:
        raise RuntimeError("boom")

    app.add_api_route("/__test-unhandled-error", boom)
    response = await client.get("/__test-unhandled-error", headers={"X-Request-ID": "rid-500"})

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal server error", "code": "internal_error", "request_id": "rid-500"}
    assert response.headers["X-Request-ID"] == "rid-500"
