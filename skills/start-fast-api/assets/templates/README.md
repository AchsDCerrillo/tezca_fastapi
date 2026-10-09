# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Stack
- **API:** FastAPI {{FASTAPI_VERSION}} · Python {{PYTHON_VERSION}}
- **Database:** {{DATABASE_LABEL}} via SQLAlchemy 2 (async) · migrations with Alembic (`sql/`)
- **Integrations:** {{INTEGRATIONS_LIST}}
- **Logging:** stdlib logging (console in dev, JSON in prod), `X-Request-ID` on every response

## Project structure
```
main.py                 FastAPI app, lifespan, middleware, /health
app/app_router.py       every feature router is registered here
app/core/               config, database, base models, exceptions + error handlers, logging, integrations
app/<feature>/          model/ (db + domain), dao, datasource, repository, service, router
sql/                    Alembic environment + versions/ (all schema changes)
tests/                  pytest: dao (no DB), service (mocked repos), api (real DB)
```
Request flow: `router → service → repository → dao / datasource → database / external`.

## Configuration
Settings live in `app/core/config.py` (pydantic-settings). `ENVIRONMENT` picks the env file:

| ENVIRONMENT | file loaded |
|---|---|
| `local` (default) | `.env.local` if present, else the defaults in `config.py` |
| `dev` | `.env.dev` |
| `prod` | `.env.prod` |

Real environment variables always win over the file. Copy `.env.example` to start:
```bash
cp .env.example .env.dev
```

## Run locally (without Docker for the API)
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
docker compose up -d db                     # only the database
ENVIRONMENT=dev alembic upgrade head        # apply migrations
ENVIRONMENT=dev uvicorn main:app --reload   # http://localhost:8000/docs
```

## Development
```bash
make install      # dev dependencies + pre-commit hook (ruff, mypy on every commit)
make format       # ruff fix + format
make lint         # ruff check + format check
make typecheck    # mypy
make test         # pytest: unit + API tests against a throwaway Postgres (needs Docker)
make check        # lint + typecheck + test
```
- **Tests:** tests live in `tests/`, mirroring `app/`. The run applies the Alembic migrations to a fresh database, and each test is rolled back.
- **Without Docker:** set `TEST_DATABASE_HOST/PORT/USER/PASSWORD/NAME` to use an existing database. `TEST_SKIP_DB=1 pytest -m "not integration"` runs only the unit tests.
- **CI:** `.github/workflows/ci.yml` runs lint, type-check, tests and a Docker build on every PR and on pushes to `main`.

## Error format
Every error response has the same shape:
```json
{"detail": "Product not found", "code": "not_found", "request_id": "3f2c9a..."}
```
Validation errors (422) add an `errors` list. Clients should switch on `code`. `request_id` matches the `X-Request-ID` response header and the logs.

## Run everything with Docker Compose
```bash
docker compose up --build        # db -> migrate (alembic upgrade head) -> api
docker compose logs -f api
docker compose down              # add -v to also delete the database volume
```
On every `up --build`, the `migrate` service applies pending migrations before the API starts.

## Database migrations (Alembic)
```bash
ENVIRONMENT=dev alembic revision --autogenerate -m "describe the change"   # after editing *_model_db.py
ENVIRONMENT=dev alembic upgrade head
ENVIRONMENT=dev alembic downgrade -1
ENVIRONMENT=dev alembic history --verbose
ENVIRONMENT=dev alembic upgrade head --sql      # print SQL only
# or inside compose:
docker compose run --rm -v "$PWD/sql/versions:/app/sql/versions" migrate alembic revision --autogenerate -m "..."
```
Always review the generated file in `sql/versions/` before applying it.

## Releases (CI/CD)
Publishing a GitHub release runs `.github/workflows/release.yml`:
1. lint + type-check + tests (the same gate as `ci.yml`);
2. build the image and push `{{IMAGE_REPOSITORY}}:<tag>`, plus `:latest` (prod) or `:dev` (dev);
3. write the new tag into `docker-compose.<env>.yml` and commit it to the default branch.

| Release tag | Environment | Compose file updated |
|---|---|---|
| `v1.4.0` | prod | `docker-compose.prod.yml` |
| `v1.4.0-dev.1`, `v1.4.0-st` | dev | `docker-compose.dev.yml` |

```bash
gh release create v1.4.0 --generate-notes                          # ship to prod
gh release create v1.4.0-dev.1 --prerelease --generate-notes       # ship to dev
```
Deploy on the server (migrations run first through the `migrate` service):
```bash
git pull
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```
**Required secrets:** {{CI_SECRETS}}. If the default branch is protected, also add `RELEASE_BOT_TOKEN` (a token with `contents: write` that can bypass the rule), so the workflow can commit the compose update.

## Build & push the image manually
```bash
IMAGE={{IMAGE_REPOSITORY}}
TAG=$(git rev-parse --short HEAD)

docker build -t {{PROJECT_SLUG}}:$TAG .
# Apple Silicon -> x86 servers:
docker buildx build --platform linux/amd64 -t {{PROJECT_SLUG}}:$TAG .

{{REGISTRY_LOGIN}}
docker tag {{PROJECT_SLUG}}:$TAG $IMAGE:$TAG
docker tag {{PROJECT_SLUG}}:$TAG $IMAGE:latest
docker push $IMAGE:$TAG
docker push $IMAGE:latest
```
Run the image standalone (migrations on start):
```bash
docker run --rm -p 8000:8000 --env-file .env.prod -e RUN_MIGRATIONS=true $IMAGE:$TAG
```

## Health checks
- `GET /health` checks that the process is up.
- `GET /health/db` checks that the database is reachable.
