"""Shared test setup.

Database: the TEST_DATABASE_* env vars (CI service container) or, if they are absent, a throwaway
Postgres started with testcontainers (needs Docker). The schema is built by running the Alembic
migrations, so every test run also proves the migrations work.

Isolation: each test runs inside a transaction that is rolled back at the end; the API's
get_session dependency is overridden to use that same session, committing/rolling back to a
SAVEPOINT per request exactly like production commits/rolls back per request.

App modules are imported inside fixtures on purpose: Settings are read at import time, and they
must see the test database env vars set in pytest_configure first.
"""

import os
import subprocess
import sys
from collections.abc import AsyncIterator
from typing import Any

import httpx
import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.pool import NullPool

_container: Any = None


def pytest_configure(config: pytest.Config) -> None:
    global _container
    if os.getenv("TEST_SKIP_DB") == "1":  # pure unit tests only: `TEST_SKIP_DB=1 pytest -m "not integration"`
        return
    os.environ["ENVIRONMENT"] = "local"
    if os.getenv("TEST_DATABASE_HOST"):
        for key in ("HOST", "PORT", "USER", "PASSWORD", "NAME"):
            os.environ[f"DATABASE_{key}"] = os.environ[f"TEST_DATABASE_{key}"]
    else:
        from testcontainers.postgres import PostgresContainer

        _container = PostgresContainer("postgres:17-alpine", username="test", password="test", dbname="test")
        _container.start()
        os.environ.update(
            DATABASE_HOST=_container.get_container_host_ip(),
            DATABASE_PORT=str(_container.get_exposed_port(5432)),
            DATABASE_USER="test",
            DATABASE_PASSWORD="test",
            DATABASE_NAME="test",
        )
    subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], check=True, env=os.environ.copy())


def pytest_unconfigure(config: pytest.Config) -> None:
    if _container is not None:
        _container.stop()


@pytest.fixture
async def db_session() -> AsyncIterator[AsyncSession]:
    from app.core.config import settings

    engine = create_async_engine(settings.database_url, poolclass=NullPool)
    async with engine.connect() as connection:
        transaction = await connection.begin()
        session = AsyncSession(bind=connection, expire_on_commit=False, join_transaction_mode="create_savepoint")
        try:
            yield session
        finally:
            await session.close()
            await transaction.rollback()
    await engine.dispose()


@pytest.fixture
async def client(db_session: AsyncSession) -> AsyncIterator[httpx.AsyncClient]:
    from app.core.database import get_session
    from main import app

    async def session_override() -> AsyncIterator[AsyncSession]:
        try:
            yield db_session
            await db_session.commit()  # releases the SAVEPOINT; the outer transaction still rolls back
        except Exception:
            await db_session.rollback()
            raise

    app.dependency_overrides[get_session] = session_override
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http_client:
        yield http_client
    app.dependency_overrides.clear()
