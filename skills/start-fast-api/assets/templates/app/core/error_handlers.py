"""Every error leaves the API with the same JSON body:

    {"detail": "Product not found", "code": "not_found", "request_id": "3f2c...", "errors": [...]}

`errors` is only present for validation failures (422)."""

import logging
from collections.abc import Mapping
from typing import Any

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette import status
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.exceptions import AppError

logger = logging.getLogger(__name__)

HTTP_STATUS_CODES = {
    400: "bad_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    422: "validation_error",
    429: "too_many_requests",
    501: "not_implemented",
    502: "external_service_error",
    503: "service_unavailable",
}


def error_response(
    request: Request,
    status_code: int,
    detail: str,
    code: str,
    errors: Any = None,
    headers: Mapping[str, str] | None = None,
) -> JSONResponse:
    body: dict[str, Any] = {
        "detail": detail,
        "code": code,
        "request_id": getattr(request.state, "request_id", None),
    }
    if errors is not None:
        body["errors"] = jsonable_encoder(errors)
    return JSONResponse(status_code=status_code, content=body, headers=headers)


async def app_error_handler(request: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, AppError)
    if exc.status_code >= 500:
        logger.error("%s: %s", exc.code, exc.message, exc_info=exc)
    return error_response(request, exc.status_code, exc.message, exc.code, exc.details)


async def http_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, StarletteHTTPException)
    code = HTTP_STATUS_CODES.get(exc.status_code, f"http_{exc.status_code}")
    return error_response(request, exc.status_code, str(exc.detail), code, headers=exc.headers)


async def validation_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, RequestValidationError)
    errors = [{"loc": list(err.get("loc", [])), "msg": err.get("msg"), "type": err.get("type")} for err in exc.errors()]
    return error_response(
        request, status.HTTP_422_UNPROCESSABLE_CONTENT, "Validation error", "validation_error", errors
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    # Fallback only: RequestContextMiddleware already turns route errors into this 500 body.
    logger.exception("unhandled exception on %s %s", request.method, request.url.path)
    return error_response(request, status.HTTP_500_INTERNAL_SERVER_ERROR, "Internal server error", "internal_error")


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, app_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)
