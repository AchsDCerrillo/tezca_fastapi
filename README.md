# tezca-fastapi

A Claude Code plugin (also installable in Codex, OpenCode, Gemini CLI, Antigravity, Copilot and Cursor) that scaffolds and grows FastAPI projects with one consistent, tested, deployable architecture.

**Version:** 0.2.0 · **Stack:** FastAPI · async SQLAlchemy 2 · Alembic · Pydantic v2 · pytest · Docker · GitHub Actions

```
router → service → repository → dao / datasource → database / external services
```

## What you get
- **A layered project with enforced boundaries.** The DAO builds queries, the repository executes them, the service holds business logic, and the router only maps HTTP.
- **Migrations that run themselves.** Alembic lives in `sql/`, and a `migrate` compose service applies pending migrations before the API starts.
- **One error format.** Services raise domain exceptions (`NotFoundError`, `ConflictError`, `BusinessRuleError`, …). Every error reaches clients as `{"detail", "code", "request_id"}`.
- **Tests in every feature.** Query tests (no database), service tests with mocked repositories, and API tests against a real Postgres, with the migrations applied and a rollback per test.
- **A quality gate.** ruff, mypy, pre-commit and `make check`, run locally and in CI.
- **CI/CD.**
  - **On every PR:** lint, types and tests.
  - **On every GitHub release:** the tests run, then the image is built and pushed to your registry (Docker Hub, GHCR, ECR or another), and the new tag is committed into `docker-compose.<env>.yml`.
- **Integrations on demand:** S3, R2, CloudFront, Redis, background jobs (ARQ), payments, JWT auth, Cognito, Secrets Manager, email, or any SDK.

## Quick start

```
/tezca-fastapi:start-fast-api        # new project: core, Docker, CI/CD, tests, README
/tezca-fastapi:add-new-feature       # "add products with name, price, status; CRUD at /products"
make check                           # ruff + mypy + pytest
docker compose up --build            # db -> migrate -> api on http://localhost:8000/docs
gh release create v0.1.0 --generate-notes   # tests -> build & push image -> compose updated
```

Every skill asks before it guesses: table columns, endpoints, error cases, registry. If a project already has code, the skill shows what exists and asks before changing it.

## Install

Repository: https://github.com/AchsDCerrillo/tezca_fastapi

### Claude Code (plugin)
In any project, from Claude Code:

```
/plugin marketplace add AchsDCerrillo/tezca_fastapi
/plugin install tezca-fastapi@tezca-fastapi-marketplace
```

> The repository is private. Anyone installing needs read access to it and git credentials (`gh auth login` or SSH). For automatic background updates, also set `GITHUB_TOKEN` (or `GH_TOKEN`) in your shell.

#### Install only at project level

Run these from the project's root folder; project scope writes to the `.claude/settings.json` of the current directory:

```bash
cd ~/code/my-api
claude plugin marketplace add AchsDCerrillo/tezca_fastapi --scope project
claude plugin install tezca-fastapi@tezca-fastapi-marketplace --scope project
```

This adds `extraKnownMarketplaces` (pointing to this repo) and `enabledPlugins` (`"tezca-fastapi@tezca-fastapi-marketplace": true`) to `.claude/settings.json`. Your other settings are kept. Commit that file: teammates who open the project in Claude Code are prompted to install the plugin.

Other ways to do the same:
- **Inside Claude Code:** `/plugin marketplace add AchsDCerrillo/tezca_fastapi`, then `/plugin`, select **tezca-fastapi**, and choose the **project** scope.
- **Installer script:** `./install-skills.sh --scope project --agents claude-plugin --project-dir ~/code/my-api`.
- **Only for you in this project:** use `--scope local`, which writes to `.claude/settings.local.json` (not committed).

Claude keeps its downloaded copy under `~/.claude/plugins/`, but the plugin is only enabled in that project.

Remove it: `claude plugin uninstall tezca-fastapi@tezca-fastapi-marketplace --scope project`.

After new plugin versions are pushed: `/plugin marketplace update tezca-fastapi-marketplace`.

During local development of the plugin itself:

```bash
claude --plugin-dir ~/Desktop/tezca_fastapi_plugin     # one session only
```

### Any agent (installer script)

```bash
git clone https://github.com/AchsDCerrillo/tezca_fastapi.git ~/tezca_fastapi
~/tezca_fastapi/install-skills.sh                      # asks: project or user level, which agents
```

#### Installer details (Claude plugin + Codex, OpenCode, Gemini CLI, Antigravity, Copilot, Cursor)

`install-skills.sh` installs everything in one go:
- **Claude Code:** `claude-plugin` installs this repo as a real plugin through the Claude marketplace. It runs `claude plugin marketplace add/update` and then `claude plugin install --scope project|user`.
- **Other agents:** the skills are copied as standalone [Agent Skills](https://agentskills.io) folders.

```bash
./install-skills.sh                                                     # interactive: asks project vs user level + agents
./install-skills.sh --scope project --agents all --project-dir ~/code/my-api
./install-skills.sh --scope user --agents codex,gemini,antigravity
./install-skills.sh --scope project --agents claude-plugin --project-dir ~/code/my-api   # Claude marketplace plugin
./install-skills.sh --dry-run ...                                       # show what would change
./install-skills.sh --uninstall --scope project --agents all --project-dir ~/code/my-api
```

| Agent | Project level | User level |
|---|---|---|
| `claude-plugin` (Claude Code, recommended) | `.claude/settings.json` via `claude plugin --scope project` | `~/.claude` via `claude plugin --scope user` |
| Codex, OpenCode, Copilot | `.agents/skills/` | `~/.agents/skills/` |
| Gemini CLI | `.agents/skills/` | `~/.gemini/skills/` |
| Antigravity | `.agents/skills/` | `~/.gemini/config/skills/` |
| Cursor | `.agents/skills/` | not supported |
| `claude` (Claude Code plain skills, skipped when `claude-plugin` is selected) | `.claude/skills/` | `~/.claude/skills/` |

How the script avoids breaking existing setups:
- **Prefixed names:** skills are installed as `tezca-<skill>` folders, so they never clash with your own skills.
- **Self-contained folders:** each folder holds its own copy of the shared conventions (`shared/`), and plugin-only paths are rewritten.
- **Marker files:** every installed folder gets a `.tezca-fastapi-install` marker. Re-running the script updates only marked folders. A same-named folder without the marker is skipped, and uninstall removes only marked folders.
- **No config edits:** the script never edits agent config files itself (settings, `opencode.json`, `AGENTS.md`, …). `claude-plugin` goes through Claude's own `claude plugin` CLI, which merges its entries into your settings and keeps everything else.
- **Marketplace source:** by default this is the repo's `origin` remote (or this folder if there is none); override it with `--marketplace-source`. Uninstalling the Claude plugin keeps the marketplace entry; remove it with `claude plugin marketplace remove tezca-fastapi-marketplace`.

Re-run the script after pulling plugin updates.

## Skills

| Skill | What it does |
|---|---|
| `/tezca-fastapi:start-fast-api` | **New project** (or bring an existing one up to standard): `app/core` (settings, async engine, base models, domain exceptions + error handlers, JSON logging, request-id middleware), `app/app_router.py`, Alembic in `sql/`, pytest harness, ruff/mypy/pre-commit/Makefile, GitHub Actions CI/CD, Dockerfile, docker-compose (db → migrate → api) plus prod/dev deployment compose files, `.env` files, README, and any integrations you choose. PostgreSQL by default; MySQL and SQLite are supported. |
| `/tezca-fastapi:add-new-feature` | **A whole feature:** models (db + domain), migration, DAO, optional datasource, repository, service, router, registration, optional background jobs, and passing tests. Finishes partially built features without breaking them. |
| `/tezca-fastapi:add-core` | **A reusable client in `app/core`:** S3, R2, CloudFront, Redis, background jobs (ARQ worker + cron), payments (Stripe or another provider), JWT security, Cognito, Secrets Manager, email, shared HTTP client, or any other SDK. |
| `/tezca-fastapi:work-dao` | **Tables and columns:** SQLAlchemy models, Pydantic mirror, DAO statements, Alembic migration (autogenerate → review → apply), DAO tests. |
| `/tezca-fastapi:work-datastore` | **A feature datasource** over a core client or a 3rd-party API, with errors that map to 502. |
| `/tezca-fastapi:work-repository` | **Repository methods** that execute DAO statements and combine datasource/core calls; they return SQLAlchemy models. |
| `/tezca-fastapi:work-service` | **Business logic + endpoint:** `(request: Request, body: Model) -> Response`, raising domain exceptions, with `build_`/`get_` factories, tests, and a route registered in `app_router.py`. |
| `/tezca-fastapi:work-tests` | **Tests:** DAO statement tests (no DB), service unit tests with mocked repositories, API tests against a real Postgres (testcontainers locally, a service container in CI). Sets up the harness if it's missing. |

The skills also trigger from plain requests ("add an orders module", "connect redis", "add a phone column to users", "write tests for the payments service").

## Generated project layout

```
main.py  alembic.ini  requirements.txt  requirements-dev.txt  pyproject.toml  Makefile
Dockerfile  docker-compose.yml  docker-compose.prod.yml  docker-compose.dev.yml
.env.example  .pre-commit-config.yaml  README.md  scripts/entrypoint.sh  worker.py (if ARQ)
.github/workflows/ci.yml       PRs + main: ruff, mypy, pytest, docker build
.github/workflows/release.yml  on release: ci.yml -> build & push image -> commit tag to compose
sql/                     env.py, script.py.mako, versions/   (Alembic, async)
app/app_router.py        every feature router is registered here
app/core/                config.py database.py models.py model_registry.py logging.py middleware.py
                         exceptions.py error_handlers.py <integrations>.py
app/<feature>/
  model/<feature>_model_db.py       SQLAlchemy
  model/<feature>_model_domain.py   Pydantic (requests / responses)
  <feature>_dao.py                  builds statements (no session)
  <feature>_datasource.py           external data (optional)
  <feature>_repository.py           executes statements, returns ORM models
  <feature>_service.py              business logic → Pydantic, raises domain exceptions, + build_/get_ factories
  <feature>_jobs.py                 background jobs (optional)
  <feature>_router.py               HTTP only
tests/conftest.py                   throwaway Postgres + migrations, db_session, client
tests/<feature>/                    test_<feature>_dao.py, _service.py, _api.py
```

## Conventions at a glance

**Errors:** services raise domain exceptions, and `app/core/error_handlers.py` turns them into HTTP responses:

| Exception | Status | `code` |
|---|---|---|
| `NotFoundError` | 404 | `not_found` |
| `ConflictError` | 409 | `conflict` |
| `BusinessRuleError` | 422 | custom per rule, e.g. `product_archived` |
| `UnauthorizedError` / `ForbiddenError` | 401 / 403 | `unauthorized` / `forbidden` |
| `ExternalServiceError` (datasource failures) | 502 | `external_service_error` or custom |
| request validation | 422 | `validation_error` + an `errors` list |
| anything unhandled | 500 | `internal_error`, logged once with the request id |

**Transactions:**
- **HTTP:** one per request (`get_session`); repositories only flush.
- **Jobs and scripts:** use `async with session_scope() as session:` with `build_<feature>_service(session)`, so they reuse the same business logic.

**Tests:** `make test` starts Postgres with testcontainers (needs Docker), runs all migrations, and rolls back each test. Without Docker, set `TEST_DATABASE_*`, or run the unit tests only with `TEST_SKIP_DB=1 pytest -m "not integration"`.

**Migrations:** `make migration m="add products"` → review the file in `sql/versions/` → `make migrate`. Every `docker compose up --build` applies pending migrations through the `migrate` service. Single-container deploys use `RUN_MIGRATIONS=true`.

## CI/CD and releases

| Release tag | Environment | Image tags pushed | Compose file updated |
|---|---|---|---|
| `v1.4.0` | prod (`APP_ENV=prod`) | `v1.4.0`, `latest` | `docker-compose.prod.yml` |
| `v1.4.0-dev.1`, `v1.4.0-st` | dev (`APP_ENV=dev`) | `v1.4.0-dev.1`, `dev` | `docker-compose.dev.yml` |

```bash
gh release create v1.4.0 --generate-notes                       # prod
gh release create v1.4.0-dev.1 --prerelease --generate-notes    # dev
# on the server:
git pull && docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d
```

**Secrets per registry:**

| Registry | Secrets |
|---|---|
| Docker Hub | `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` |
| GHCR | none |
| ECR | `AWS_ROLE_ARN` (OIDC) |
| Other | `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` |

If `main` is protected, also add `RELEASE_BOT_TOKEN`, so the workflow can commit the compose update. The release triggers on `published`, not `created`, so saving a draft release ships nothing.

## Repository layout

```
.claude-plugin/plugin.json, marketplace.json
references/               shared conventions every skill reads:
                          architecture, models, dao, datasource, repository, service, router,
                          migrations, testing, background_jobs, integrations/*
skills/<skill>/SKILL.md   workflows
skills/start-fast-api/assets/templates/   the files copied into new projects
skills/start-fast-api/references/         databases.md, ci.md (registry blocks, release flow)
install-skills.sh         installs into Claude (marketplace) and other agents
```

To change a convention, edit it in `references/`; every skill picks it up. Bump `version` in `.claude-plugin/plugin.json` and `marketplace.json` when you publish changes.

## Changelog

**0.2.0**
- **Errors:** domain exceptions and one JSON error format. 500 responses keep `X-Request-ID` and are logged once.
- **Tests:** a pytest harness (testcontainers, migrations, rollback per test), the new `work-tests` skill, and tests generated with every feature.
- **Tooling:** ruff, mypy, pre-commit and a Makefile.
- **Background work:** `session_scope()`, `build_<feature>_service`, and the ARQ recipe for jobs and cron.
- **CI/CD:** `ci.yml` and `release.yml` (tests → push to any registry → tag committed to compose), plus prod/dev deployment compose files.

**0.1.0**
- First release: 7 skills, the layered architecture, Alembic, Docker with a migrate service, integrations, and the multi-agent installer.
