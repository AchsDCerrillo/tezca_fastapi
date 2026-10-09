ARG PYTHON_VERSION={{PYTHON_VERSION}}

# ---- builder: install dependencies into a venv ----
FROM python:${PYTHON_VERSION}-slim AS builder
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
WORKDIR /build
COPY requirements.txt .
RUN pip install -r requirements.txt

# ---- runtime: slim image, non-root user ----
FROM python:${PYTHON_VERSION}-slim AS runtime
# APP_ENV is set by the release workflow (dev for -dev/-st tags, prod otherwise); a runtime
# ENVIRONMENT variable (compose, ECS...) still overrides it.
ARG APP_ENV=prod
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ENVIRONMENT=${APP_ENV} \
    PATH="/opt/venv/bin:$PATH"
RUN useradd --create-home --uid 1000 app
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app . .
RUN chmod +x scripts/entrypoint.sh
USER app

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status == 200 else 1)"

# entrypoint runs `alembic upgrade head` first when RUN_MIGRATIONS=true, then execs CMD
ENTRYPOINT ["scripts/entrypoint.sh"]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
