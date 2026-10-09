#!/bin/sh
set -e

# Apply pending Alembic migrations before starting (used by single-container deploys such as ECS/App Runner).
# docker compose uses the dedicated `migrate` service instead.
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    echo "Running database migrations..."
    alembic upgrade head
fi

exec "$@"
