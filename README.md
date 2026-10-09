# tezca-fastapi: Claude Code plugin

Scaffold and grow FastAPI projects with one consistent layered architecture.

```
router → service → repository → dao / datasource → database / external services
```

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
| `/tezca-fastapi:start-fast-api` | New project (or bring an existing one up to standard): `app/core` (settings, async engine, base models, domain exceptions + one JSON error format, logging, request-id middleware), `app/app_router.py`, Alembic in `sql/`, pytest harness, ruff/mypy/pre-commit/Makefile, GitHub Actions CI/CD (lint + tests on PRs; on each release: tests → build → push to any registry → new tag committed into `docker-compose.<env>.yml`), Dockerfile, docker-compose (db → **migrate** → api), `.env` files, README, plus any integrations you choose. PostgreSQL by default. |
| `/tezca-fastapi:add-new-feature` | A whole feature: models (db + domain), migration, DAO, optional datasource, repository, service, router, registration, optional background jobs, and tests that pass. Finishes partially built features without breaking them. |
| `/tezca-fastapi:add-core` | A reusable client in `app/core`: S3, R2, CloudFront, Redis, background jobs (ARQ worker + cron), payments (Stripe or another provider), JWT security, Cognito, Secrets Manager, email, shared HTTP client, or any other SDK. |
| `/tezca-fastapi:work-dao` | Tables and columns: SQLAlchemy models, Pydantic mirror, DAO statements, Alembic migration (autogenerate → review → apply). |
| `/tezca-fastapi:work-datastore` | A feature datasource over a core client or a 3rd-party API. |
| `/tezca-fastapi:work-repository` | Repository methods that execute DAO statements and combine datasource/core calls; they return SQLAlchemy models. |
| `/tezca-fastapi:work-tests` | Tests per feature: DAO statement tests (no DB), service unit tests with mocked repositories, API tests against a real Postgres (testcontainers / CI service), run against the real migrations. Sets up the harness if missing. |
| `/tezca-fastapi:work-service` | Business logic + endpoint: `(request: Request, body: Model) -> Response` raising domain exceptions (`NotFoundError`, `ConflictError`, …), `build_`/`get_` factories, tests, and a route registered in `app_router.py`. |

The skills also trigger from plain requests ("add an orders module", "connect redis", "add a phone column to users").

## Generated project layout

```
main.py  alembic.ini  requirements.txt  requirements-dev.txt  pyproject.toml  Makefile
Dockerfile  docker-compose.yml  .env.example  README.md  .pre-commit-config.yaml
.github/workflows/ci.yml  .github/workflows/release.yml  docker-compose.prod.yml  docker-compose.dev.yml
scripts/entrypoint.sh  worker.py (if ARQ)
sql/                     env.py, script.py.mako, versions/   (Alembic, async)
app/app_router.py        every feature router is registered here
app/core/                config.py database.py models.py model_registry.py logging.py middleware.py
                         exceptions.py error_handlers.py <integrations>.py
app/<feature>/
  model/<feature>_model_db.py       SQLAlchemy
  model/<feature>_model_domain.py   Pydantic
  <feature>_dao.py                  builds statements (no session)
  <feature>_datasource.py           external data (optional)
  <feature>_repository.py           executes statements, returns ORM models
  <feature>_service.py              business logic → Pydantic, raises domain exceptions, + build_/get_ factories
  <feature>_jobs.py                 optional background jobs
  <feature>_router.py               HTTP only
tests/<feature>/                    test_<feature>_dao.py, _service.py, _api.py
```

Every error reaches clients as `{"detail", "code", "request_id"}`. Quality gate: `make check` (ruff, mypy, pytest), also run in CI.

Shipping: `gh release create v1.4.0 --generate-notes`. The release workflow runs the tests, pushes `IMAGE:v1.4.0` (+ `latest`) and commits the new tag into `docker-compose.prod.yml`. Tags containing `-dev`/`-st` go to `docker-compose.dev.yml` instead.

Migrations:
- Every `docker compose up --build` runs the `migrate` service (`alembic upgrade head`) before the API starts.
- Single-container deploys use `RUN_MIGRATIONS=true`.

## Repository layout

```
.claude-plugin/plugin.json, marketplace.json
references/               shared conventions every skill reads (architecture, models, dao, datasource,
                          repository, service, router, migrations, integrations/*)
skills/<skill>/SKILL.md   workflows
skills/start-fast-api/assets/templates/   the files copied into new projects
install-skills.sh         installs the skills into other agents (Codex, OpenCode, Gemini, ...)
```

To change a convention, edit it in `references/`. All skills pick it up.
