# tezca-fastapi: Claude Code plugin

Scaffold and grow FastAPI projects with one consistent layered architecture.

```
router → service → repository → dao / datasource → database / external services
```

## Install

Push this folder to a git repository, then in any project:

```
/plugin marketplace add <git-url-or-owner/repo>
/plugin install tezca-fastapi@tezca-fastapi-marketplace
```

During local development of the plugin itself:

```
/plugin marketplace add ~/Desktop/tezca_fastapi_plugin
/plugin install tezca-fastapi@tezca-fastapi-marketplace
# or, for one session only:
claude --plugin-dir ~/Desktop/tezca_fastapi_plugin
```

After pulling new plugin changes: `/plugin marketplace update tezca-fastapi-marketplace`.

### Other agents (Codex, OpenCode, Gemini CLI, Antigravity, Copilot, Cursor)

`install-skills.sh` copies the skills, as standalone [Agent Skills](https://agentskills.io) folders, into other agents:

```bash
./install-skills.sh                                                     # interactive: asks project vs user level + agents
./install-skills.sh --scope project --agents all --project-dir ~/code/my-api
./install-skills.sh --scope user --agents codex,gemini,antigravity
./install-skills.sh --dry-run ...                                       # show what would change
./install-skills.sh --uninstall --scope project --agents all --project-dir ~/code/my-api
```

| Agent | Project level | User level |
|---|---|---|
| Codex, OpenCode, Copilot | `.agents/skills/` | `~/.agents/skills/` |
| Gemini CLI | `.agents/skills/` | `~/.gemini/skills/` |
| Antigravity | `.agents/skills/` | `~/.gemini/config/skills/` |
| Cursor | `.agents/skills/` | not supported |
| Claude Code (plain skills) | `.claude/skills/` | `~/.claude/skills/` |

How the script avoids breaking existing setups:
- **Prefixed names:** skills are installed as `tezca-<skill>` folders, so they never clash with your own skills.
- **Self-contained folders:** each folder holds its own copy of the shared conventions (`shared/`), and plugin-only paths are rewritten.
- **Marker files:** every installed folder gets a `.tezca-fastapi-install` marker. Re-running the script updates only marked folders. A same-named folder without the marker is skipped, and uninstall removes only marked folders.
- **No config edits:** agent config files (settings, `opencode.json`, `AGENTS.md`, …) are never touched.

Re-run the script after pulling plugin updates.

## Skills

| Skill | What it does |
|---|---|
| `/tezca-fastapi:start-fast-api` | New project (or bring an existing one up to standard): `app/core` (settings, async engine, base models, logging, request-id middleware), `app/app_router.py`, Alembic in `sql/`, Dockerfile, docker-compose (db → **migrate** → api), `.env` files, README with build/push commands, plus any integrations you choose. PostgreSQL by default. |
| `/tezca-fastapi:add-new-feature` | A whole feature: models (db + domain), migration, DAO, optional datasource, repository, service, router, registration. Finishes partially built features without breaking them. |
| `/tezca-fastapi:add-core` | A reusable client in `app/core`: S3, R2, CloudFront, Redis, payments (Stripe or another provider), JWT security, Cognito, Secrets Manager, email, shared HTTP client, or any other SDK. |
| `/tezca-fastapi:work-dao` | Tables and columns: SQLAlchemy models, Pydantic mirror, DAO statements, Alembic migration (autogenerate → review → apply). |
| `/tezca-fastapi:work-datastore` | A feature datasource over a core client or a 3rd-party API. |
| `/tezca-fastapi:work-repository` | Repository methods that execute DAO statements and combine datasource/core calls; they return SQLAlchemy models. |
| `/tezca-fastapi:work-service` | Business logic + endpoint: `(request: Request, body: Model) -> Response`, starlette `HTTPException`/`status`, a DI factory, and a route registered in `app_router.py`. |

The skills also trigger from plain requests ("add an orders module", "connect redis", "add a phone column to users").

## Generated project layout

```
main.py  alembic.ini  requirements.txt  Dockerfile  docker-compose.yml  .env.example  README.md
scripts/entrypoint.sh
sql/                     env.py, script.py.mako, versions/   (Alembic, async)
app/app_router.py        every feature router is registered here
app/core/                config.py database.py models.py model_registry.py logging.py middleware.py <integrations>.py
app/<feature>/
  model/<feature>_model_db.py       SQLAlchemy
  model/<feature>_model_domain.py   Pydantic
  <feature>_dao.py                  builds statements (no session)
  <feature>_datasource.py           external data (optional)
  <feature>_repository.py           executes statements, returns ORM models
  <feature>_service.py              business logic → Pydantic, + get_<feature>_service()
  <feature>_router.py               HTTP only
```

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
