---
name: start-fast-api
description: Scaffold a new production-ready FastAPI project (or bring an existing one up to standard) using the Tezca layered architecture - app/core (pydantic-settings config, async SQLAlchemy engine, base models, JSON logging, request-id middleware), app/app_router.py, Alembic migrations in sql/, Dockerfile, docker-compose with an automatic migrate step, .env files and a README with build/push commands. PostgreSQL by default; MySQL/SQLite on request; optional integrations (S3, R2, CloudFront, Redis, Stripe/payments, JWT security, Cognito, Secrets Manager, SES). Use this skill whenever the user wants to start, bootstrap, init, create or set up a FastAPI / Python API / backend project, asks for "the base project", "project skeleton", "core folder", or wants Docker + Alembic + config added to a FastAPI repo that lacks them - even if they don't say "scaffold".
---

# start-fast-api

Creates the foundation every other Tezca skill builds on. Once this skill has run, `add-new-feature`, `add-core` and the `work-*` skills can drop features into the project without guessing where things go.

## Where things are
- **Shared conventions:** `${CLAUDE_PLUGIN_ROOT}/references/`. This is `../../references/` relative to this skill's base directory. Read `architecture.md` before you start; it defines the tree you are about to create.
- **File templates:** `assets/templates/` in this skill. Copy them verbatim, then replace the `{{PLACEHOLDERS}}`.
- **Database-specific values:** `references/databases.md` in this skill.
- **Integration recipes:** `${CLAUDE_PLUGIN_ROOT}/references/integrations/*.md`.

## Step 1: Inspect the target directory

Work in the current working directory unless the user names another one. Run the detection commands from `architecture.md` §5.

- **Empty or new directory:** continue.
- **Existing project:** list what already exists (core files, Alembic, Docker, routers, where `Base` lives) and which pieces are missing. Ask the user whether to:
  - (a) add only the missing pieces, adapting to the existing code;
  - (b) restructure toward the Tezca layout; or
  - (c) stop.

  Never overwrite an existing file without showing the user what would change and getting a yes. Their working code matters more than template purity.

## Step 2: Ask what to build

Ask in **one** message, grouped. Offer the default for each question so the user can just say "defaults". Don't invent answers the user didn't give; a wrong guess here spreads into every later file.

1. **Project name**, plus a one-line description for the README.
2. **Database:** PostgreSQL (default), MySQL or SQLite.
3. **Integrations** to add now: S3, Cloudflare R2, CloudFront, Redis, payments (Stripe or another provider), JWT security (own auth), AWS Cognito, AWS Secrets Manager, email (SES or other), shared HTTP client for 3rd-party APIs, or none.
   For each chosen integration, ask its details in this same round (see the "Ask before writing" step in `add-core`), e.g. local MinIO or not, a Redis compose service, Secrets Manager at startup or runtime. That way add-core doesn't have to ask again.
4. **Container registry** for the README push commands: AWS ECR (needs account id + region), Docker Hub (user/org), GHCR (org), or other.
5. **Python version** for the Docker image (default `3.13`).
6. **Global API prefix** (default none; e.g. `/api/v1`).

## Step 3: Generate the files

Derive the values:
- `PROJECT_SLUG`: kebab-case for the image/compose name.
- `DATABASE_NAME`: snake_case.
- Database placeholders: from `references/databases.md`.
- `FASTAPI_VERSION`: from the templates' `requirements.txt`.

Copy every file under `assets/templates/` to the project, keeping relative paths:

```
main.py  alembic.ini  requirements.txt  Dockerfile  docker-compose.yml  README.md
.env.example  .gitignore  .dockerignore  scripts/entrypoint.sh
app/__init__.py (create empty)  app/app_router.py
app/core/{__init__,config,database,models,model_registry,logging,middleware}.py
sql/env.py  sql/script.py.mako  sql/versions/.gitkeep (create empty)
```

Then:
- Replace every `{{PLACEHOLDER}}`. Afterwards, `grep -rn "{{" .` must find nothing. (`sql/script.py.mako` legitimately contains Mako `${...}` expressions; leave them.)
- **Port clashes:** check the host ports are free (`lsof -i :8000`, the DB port, etc.). If one is taken, change only the host side of the compose mapping (e.g. `"18000:8000"`, or `DATABASE_PORT=55432` → `"55432:5432"`) and mention it in the README.
- Run `chmod +x scripts/entrypoint.sh`.
- Create `.env.dev` from `.env.example`, with local-friendly values (`DATABASE_HOST=localhost`). Create `.env.prod` with the same keys and empty secrets. Both are git-ignored.
- Set `api_prefix` default in `config.py` if the user chose one.
- **README registry block:** fill `IMAGE_REPOSITORY` and `REGISTRY_LOGIN`:

| Registry | `IMAGE_REPOSITORY` | `REGISTRY_LOGIN` |
|---|---|---|
| ECR | `<account>.dkr.ecr.<region>.amazonaws.com/<slug>` | `aws ecr get-login-password --region <region> \| docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com`, plus a comment: `aws ecr create-repository --repository-name <slug>` (first time only) |
| Docker Hub | `<user>/<slug>` | `docker login` |
| GHCR | `ghcr.io/<org>/<slug>` | `echo $GITHUB_TOKEN \| docker login ghcr.io -u <user> --password-stdin` |

- **Integrations:** for each chosen one, follow the `add-core` workflow (read `${CLAUDE_PLUGIN_ROOT}/skills/add-core/SKILL.md` and the matching integration reference). That workflow adds the core class, the settings, the env keys, the requirements, any compose service, and lifespan cleanup. Fill `INTEGRATIONS_LIST` in the README.

### Why these choices (so you can explain them, or adapt when asked)
- **One transaction per request:** `get_session` commits or rolls back for the whole request, so repositories only `flush`.
- **No `create_all` at startup:** Alembic owns the schema. Startup DDL can't alter tables and races with migrations.
- **The `migrate` compose service:** it runs `alembic upgrade head` from the same image before `api` starts (`service_completed_successfully`). Every `docker compose up --build` therefore applies new migrations automatically. `RUN_MIGRATIONS=true` does the same for single-container deploys.
- **The `.dockerignore` excludes `.env.*`:** secrets never get baked into images; compose and the runtime inject them.
- **`model_registry.py`:** Alembic only sees models whose modules are imported, and this file is where they are imported.

## Step 4: Verify

```bash
python -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
python -c "import main; print('import ok')"
```
If Docker is running, and only with the user's go-ahead, because it starts containers:
```bash
docker compose up --build -d && sleep 5 && curl -s localhost:8000/health && curl -s localhost:8000/health/db
docker compose logs migrate | tail -5
```
Fix anything that fails before reporting.

## Step 5: Report
Finish with:
- the tree of created and modified files;
- which integrations were added;
- the commands to run next (local run, compose, first migration).

Suggest the natural next step: `/tezca-fastapi:add-new-feature` to create the first feature.
