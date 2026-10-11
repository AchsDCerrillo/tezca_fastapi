---
name: start-fast-api
description: Scaffold a new production-ready FastAPI project (or bring an existing one up to standard) using the Tezca layered architecture - app/core (pydantic-settings config, async SQLAlchemy engine, base models, domain exceptions + one JSON error format, JSON logging, request-id middleware), app/app_router.py, a pytest harness (testcontainers Postgres, rollback per test), ruff + mypy + pre-commit + Makefile, GitHub Actions CI/CD (lint + tests on every PR; on each published release - tests, Docker build, push to Docker Hub/GHCR/ECR/any registry, and the new image tag committed into docker-compose.<env>.yml), Alembic migrations in sql/, Dockerfile, docker-compose with an automatic migrate step, .env files and a README with build/push commands. PostgreSQL by default; MySQL/SQLite on request; optional integrations (S3, R2, CloudFront, Redis, Stripe/payments, JWT security, Cognito, Secrets Manager, SES). Use this skill whenever the user wants to start, bootstrap, init, create or set up a FastAPI / Python API / backend project, asks for "the base project", "project skeleton", "core folder", or wants Docker + Alembic + config added to a FastAPI repo that lacks them - even if they don't say "scaffold".
---

# start-fast-api

Creates the foundation every other Tezca skill builds on. Once this skill has run, `add-new-feature`, `add-core` and the `work-*` skills can drop features into the project without guessing where things go.

## Where things are
- **Shared conventions:** `${CLAUDE_PLUGIN_ROOT}/references/`. This is `../../references/` relative to this skill's base directory. Read `architecture.md` before you start; it defines the tree you are about to create.
- **File templates:** `assets/templates/` in this skill. Copy them verbatim, then replace the `{{PLACEHOLDERS}}`.
- **Database-specific values:** `references/databases.md` in this skill.
- **CI/CD (workflows, registry login blocks, release flow):** `references/ci.md` in this skill.
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
3. **Integrations** to add now: S3, Cloudflare R2, CloudFront, Redis, background jobs (ARQ, needs Redis), payments (Stripe or another provider), JWT security (own auth), AWS Cognito, AWS Secrets Manager, email (SES or other), shared HTTP client for 3rd-party APIs, or none.
   For each chosen integration, ask its details in this same round (see the "Ask before writing" step in `add-core`), e.g. local MinIO or not, a Redis compose service, Secrets Manager at startup or runtime. That way add-core doesn't have to ask again.
4. **Container registry** for the README push commands and CI: AWS ECR (needs account id + region), Docker Hub (user/org), GHCR (org), or other.
5. **CI/CD:** GitHub Actions (default yes). This means `ci.yml` for PRs, plus `release.yml`, which publishes the image on each GitHub release and commits the new tag into `docker-compose.<env>.yml`. Ask:
   - whether the release pipeline is wanted (default yes);
   - whether the default branch is protected (then a `RELEASE_BOT_TOKEN` secret is needed);
   - whether the tag convention `-dev`/`-st` → dev, otherwise prod, fits, or which environments they use.
6. **Python version** for the Docker image, CI and tooling (default `3.13`).
7. **Global API prefix** (default none; e.g. `/api/v1`).

## Step 3: Generate the files

Derive the values:
- `PROJECT_SLUG`: kebab-case for the image/compose name.
- `DATABASE_NAME`: snake_case.
- Database placeholders: from `references/databases.md`.
- `FASTAPI_VERSION`: from the templates' `requirements.txt`.

Copy every file under `assets/templates/` to the project, keeping relative paths:

```
main.py  alembic.ini  requirements.txt  requirements-dev.txt  pyproject.toml  Makefile
Dockerfile  docker-compose.yml  README.md  .env.example  .gitignore  .dockerignore
.pre-commit-config.yaml  .github/workflows/ci.yml  .github/workflows/release.yml (skip if declined)
docker-compose.prod.yml  docker-compose.dev.yml (deployment compose files the release updates)
scripts/entrypoint.sh
app/__init__.py (create empty)  app/app_router.py
app/core/{__init__,config,database,models,model_registry,logging,middleware,exceptions,error_handlers}.py
sql/env.py  sql/script.py.mako  sql/versions/.gitkeep (create empty)
tests/__init__.py (create empty)  tests/conftest.py  tests/test_health.py
```

Then:
- Replace every `{{PLACEHOLDER}}`. Afterwards, `grep -rnE "\{\{[A-Z_]+\}\}" .` must find nothing. (GitHub Actions `${{ ... }}` expressions and Mako `${...}` in `sql/script.py.mako` are legitimate; leave them.)
- **CI/CD:** follow `references/ci.md`.
  - In `release.yml`, replace the `# {{REGISTRY_LOGIN_STEPS}}` line with the chosen registry's login block.
  - Set `IMAGE_REPOSITORY` everywhere: `release.yml`, `docker-compose.{prod,dev}.yml`, README.
  - Adapt the `ci.yml` database service if the database isn't Postgres.
  - Add or remove environments if the user's tag convention differs.
  - Keep the `# release-image` markers in the deployment compose files; the release job rewrites only those lines.
  - If the user declined the release pipeline, skip `release.yml` and the deployment compose files.
- **Port clashes:** check the host ports are free (`lsof -i :8000`, the DB port, etc.). If one is taken, change only the host side of the compose mapping (e.g. `"18000:8000"`, or `DATABASE_PORT=55432` → `"55432:5432"`) and mention it in the README.
- Run `chmod +x scripts/entrypoint.sh`.
- Create `.env.dev` from `.env.example`, with local-friendly values (`DATABASE_HOST=localhost`, the compose host port).
- Create `.env.prod` with the same keys, `ENVIRONMENT=prod`, `DEBUG=false` and `LOG_LEVEL=INFO`. Set `DATABASE_PORT` to the engine's default (5432/3306), not the local host port. Leave `DATABASE_HOST` and every secret/password empty for the user to fill. Both files are git-ignored.
- Set `api_prefix` default in `config.py` if the user chose one.
- **README registry block:** fill `IMAGE_REPOSITORY`, `REGISTRY_LOGIN` and `CI_SECRETS`:

| Registry | `IMAGE_REPOSITORY` | `REGISTRY_LOGIN` | `CI_SECRETS` |
|---|---|---|---|
| ECR | `<account>.dkr.ecr.<region>.amazonaws.com/<slug>` | `aws ecr get-login-password --region <region> \| docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com`, plus a comment: `aws ecr create-repository --repository-name <slug>` (first time only) | `AWS_ROLE_ARN` (OIDC role with ECR push) |
| Docker Hub | `<user>/<slug>` | `docker login` | `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` |
| GHCR | `ghcr.io/<org>/<slug>` | `echo $GITHUB_TOKEN \| docker login ghcr.io -u <user> --password-stdin` | none (uses the workflow's `GITHUB_TOKEN`) |
| Other | `<host>/<path>/<slug>` | `docker login <host>` | `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` |

- **Integrations:** for each chosen one, follow the `add-core` workflow (read `${CLAUDE_PLUGIN_ROOT}/skills/add-core/SKILL.md` and the matching integration reference). That workflow adds the core class, the settings, the env keys, the requirements, any compose service, and lifespan cleanup. Fill `INTEGRATIONS_LIST` in the README.

### Why these choices (so you can explain them, or adapt when asked)
- **One transaction per request:** `get_session` commits or rolls back for the whole request, so repositories only `flush`.
- **No `create_all` at startup:** Alembic owns the schema. Startup DDL can't alter tables and races with migrations.
- **The `migrate` compose service:** it runs `alembic upgrade head` from the same image before `api` starts (`service_completed_successfully`). Every `docker compose up --build` therefore applies new migrations automatically. `RUN_MIGRATIONS=true` does the same for single-container deploys.
- **The `.dockerignore` excludes `.env.*`:** secrets never get baked into images; compose and the runtime inject them.
- **Domain exceptions + `error_handlers.py`:** services raise `NotFoundError`/`ConflictError`/…, never HTTP types, so the same logic runs from routes, jobs and scripts. Every error reaches clients as `{"detail", "code", "request_id"}`.
- **Tests run the Alembic migrations** against a throwaway Postgres (testcontainers locally, a service container in CI), so a broken migration fails the build. Each test runs in a rolled-back transaction.
- **Release pipeline:** `release.yml` reuses `ci.yml` (`workflow_call`), so no image is published without passing lint and tests. The compose file in git records which image each environment should run; deploying is `pull && up -d` on the server, with migrations applied by the `migrate` service.
- **`session_scope()`** is the unit of work for code outside HTTP (see `${CLAUDE_PLUGIN_ROOT}/references/background_jobs.md`).
- **`model_registry.py`:** Alembic only sees models whose modules are imported, and this file is where they are imported.

## Step 4: Verify

```bash
python -m venv .venv && . .venv/bin/activate && make install     # dev deps + pre-commit hook
make format && make lint typecheck                                 # must be clean
make test                                                          # needs Docker (testcontainers)
python -c "import main; print('import ok')"
```
If the project isn't a git repository yet, offer to run `git init` before `make install`; pre-commit needs one. pre-commit only checks files git knows about, so stage the files (`git add -A`) before `pre-commit run --all-files`.
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
- the lint, type-check and test results;
- the commands to run next (`make run`, `make up`, `make test`, first migration);
- the CI/CD checklist from `references/ci.md`: secrets to create (Docker Hub token, `AWS_ROLE_ARN`, `RELEASE_BOT_TOKEN` if the branch is protected) and how to ship (`gh release create v0.1.0 --generate-notes`).

Suggest the natural next step: `/tezca-fastapi:add-new-feature` to create the first feature (it comes with tests).
