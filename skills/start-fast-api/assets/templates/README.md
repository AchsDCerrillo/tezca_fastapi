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
app/core/               config, database, base models, logging, integrations
app/<feature>/          model/ (db + domain), dao, datasource, repository, service, router
sql/                    Alembic environment + versions/ (all schema changes)
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
docker compose run --rm migrate alembic revision --autogenerate -m "..."
```
Always review the generated file in `sql/versions/` before applying it.

## Build & push the image
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
