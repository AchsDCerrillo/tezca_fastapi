"""Domain exceptions raised by services (and core/datasources). They carry no HTTP knowledge beyond a
default status; app/core/error_handlers.py turns them into the standard error response, so business
logic can be reused from HTTP routes, CLI commands and background workers alike."""

from typing import Any


class AppError(Exception):
    status_code: int = 400
    code: str = "bad_request"
    message: str = "Bad request"

    def __init__(self, message: str | None = None, *, code: str | None = None, details: Any = None):
        self.message = message or self.message
        self.code = code or self.code
        self.details = details
        super().__init__(self.message)


class BadRequestError(AppError):
    status_code = 400
    code = "bad_request"
    message = "Bad request"


class UnauthorizedError(AppError):
    status_code = 401
    code = "unauthorized"
    message = "Not authenticated"


class ForbiddenError(AppError):
    status_code = 403
    code = "forbidden"
    message = "Not allowed"


class NotFoundError(AppError):
    status_code = 404
    code = "not_found"
    message = "Resource not found"


class ConflictError(AppError):
    status_code = 409
    code = "conflict"
    message = "Resource already exists"


class BusinessRuleError(AppError):
    status_code = 422
    code = "business_rule_violation"
    message = "Business rule violated"


class ExternalServiceError(AppError):
    """A third-party provider (payments, storage, external API) failed. Datasource errors subclass this."""

    status_code = 502
    code = "external_service_error"
    message = "External service unavailable"


class NotImplementedAppError(AppError):
    """Placeholder body for scaffolded service methods."""

    status_code = 501
    code = "not_implemented"
    message = "Not implemented"
