import logging
import logging.config
from contextvars import ContextVar

from app.core.config import settings

request_id_ctx: ContextVar[str] = ContextVar("request_id", default="-")


class RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_ctx.get()
        return True


def setup_logging() -> None:
    """Readable console logs locally/dev, one JSON object per line in prod (CloudWatch/Datadog friendly)."""
    formatter = "json" if settings.is_prod else "console"
    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "filters": {"request_id": {"()": RequestIdFilter}},
            "formatters": {
                "console": {
                    "format": "%(asctime)s %(levelname)-8s [%(request_id)s] %(name)s: %(message)s",
                },
                "json": {
                    "()": "pythonjsonlogger.json.JsonFormatter",
                    "fmt": "%(asctime)s %(levelname)s %(name)s %(request_id)s %(message)s",
                    "rename_fields": {"asctime": "timestamp", "levelname": "level"},
                },
            },
            "handlers": {
                "default": {
                    "class": "logging.StreamHandler",
                    "formatter": formatter,
                    "filters": ["request_id"],
                    "stream": "ext://sys.stdout",
                },
            },
            "root": {"handlers": ["default"], "level": settings.log_level},
            "loggers": {
                "uvicorn": {"handlers": ["default"], "level": settings.log_level, "propagate": False},
                "uvicorn.error": {"handlers": ["default"], "level": settings.log_level, "propagate": False},
                # access logs come from RequestContextMiddleware instead
                "uvicorn.access": {"handlers": [], "level": "WARNING", "propagate": False},
                "sqlalchemy.engine": {"level": "INFO" if settings.database_echo else "WARNING"},
            },
        }
    )
