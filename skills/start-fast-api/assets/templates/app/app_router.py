"""Single place where every feature router is registered. main.py only includes this router.

Add one import + include_router line per feature, e.g.:
    from app.product.product_router import router as product_router
    router.include_router(product_router)
"""

from fastapi import APIRouter

router = APIRouter()
