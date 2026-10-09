from collections.abc import AsyncGenerator
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings


def _engine_kwargs() -> dict[str, Any]:
    kwargs: dict[str, Any] = {"echo": settings.database_echo, "pool_pre_ping": True}
    if not settings.database_driver.startswith("sqlite"):
        kwargs |= {"pool_size": settings.database_pool_size, "max_overflow": settings.database_max_overflow}
    return kwargs


engine = create_async_engine(settings.database_url, **_engine_kwargs())

async_session_factory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """One session (= one transaction) per request: commit on success, rollback on any exception."""
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def close_db() -> None:
    await engine.dispose()
