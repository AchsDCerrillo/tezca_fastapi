import logging
import time
import uuid

from starlette import status
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.core.error_handlers import error_response
from app.core.logging import request_id_ctx

logger = logging.getLogger("app.access")


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Assigns a request id (honours X-Request-ID), exposes it on request.state, logs one access line,
    and turns unhandled exceptions into the standard 500 body - here rather than in an exception
    handler so the response still carries X-Request-ID and the error is logged once, with its id."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex
        request.state.request_id = request_id
        token = request_id_ctx.set(request_id)
        start = time.perf_counter()
        try:
            try:
                response = await call_next(request)
            except Exception:
                logger.exception("unhandled error %s %s", request.method, request.url.path)
                response = error_response(
                    request, status.HTTP_500_INTERNAL_SERVER_ERROR, "Internal server error", "internal_error"
                )
            response.headers["X-Request-ID"] = request_id
            logger.info(
                "%s %s %s %.1fms",
                request.method,
                request.url.path,
                response.status_code,
                (time.perf_counter() - start) * 1000,
            )
            return response
        finally:
            request_id_ctx.reset(token)
