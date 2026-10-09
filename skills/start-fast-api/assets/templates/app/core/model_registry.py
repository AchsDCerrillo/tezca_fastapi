"""Imports every SQLAlchemy model module so Alembic autogenerate and relationship resolution can see them.

Add one line per feature model file:
    import app.product.model.product_model_db  # noqa: F401
"""

from app.core.models import Base

__all__ = ["Base"]
