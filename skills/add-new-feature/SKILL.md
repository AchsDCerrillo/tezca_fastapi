---
name: add-new-feature
description: Build a complete feature end-to-end in a Tezca FastAPI project - SQLAlchemy + Pydantic models, Alembic migration, DAO, optional datasource, repository, service (filled or empty scaffold) and router registered in app/app_router.py - or finish a half-built feature without breaking what exists. Use whenever the user wants to add a new resource/module/domain/entity/endpoint group ("add products", "we need an orders module with these tables", "create the CRUD for invoices", "finish the api_key feature") to a FastAPI project, even if they describe it only in terms of tables or endpoints.
---

# add-new-feature

This skill orchestrates the layer skills in the right order, so that a feature arrives complete and consistent: tables → statements → (external data) → operations → business logic → HTTP.

**Read first:** in `${CLAUDE_PLUGIN_ROOT}/references/` (`../../references/` from this skill's base directory):
- `architecture.md`: tree, call graph, naming;
- then, as you reach each layer, `models.md`, `dao.md`, `migrations.md`, `datasource.md`, `repository.md`, `service.md` and `router.md`.

The `work-*` skills in `${CLAUDE_PLUGIN_ROOT}/skills/` hold the per-layer workflows. Follow their steps for each layer, but merge their questions into the single round below so the user isn't interrogated six times.

## Step 1: Check the project and the feature's current state
- **Project setup:** if `app/core/` or `app/app_router.py` is missing, offer `start-fast-api` first.
- **Existing layers:** look for `app/<feature>/` (and similar names: plural/singular, nested paths). For each layer (`model_db`, `model_domain`, `dao`, `datasource`, `repository`, `service`, `router`, registry entry, router registration, migration), mark it **missing**, **partial** (e.g. stub routes, no response models, Base declared in the wrong place) or **done**.
- **If anything exists:** show that status table and ask:
  - Should existing pieces be changed, or only the missing ones completed?
  - For each partial piece, keep it as-is or bring it up to the conventions?

  Never rewrite working code silently.

## Step 2: One round of questions (ask, don't infer)
Group these into one message, offering defaults where the plugin has them:
1. **Name and location:** feature name and folder (nested? e.g. `app/project/api_key`), plus the URL prefix.
2. **Data:**
   - tables and columns (type, nullable, default, unique, index);
   - enums;
   - relationships/FKs with `ondelete`;
   - UUID vs int ids; timestamps.
   For changes to existing tables, also ask how to handle existing rows.
3. **External data:** does the feature need a datasource (storage, cache, a 3rd-party API)? Which one, and is the core client already present?
4. **Endpoints:** for each one, method + path, request model, response model, success status, auth. Default offer: standard CRUD (`POST`, `GET list` with filters + pagination, `GET by id`, `PATCH`, `DELETE`).
5. **Service:** filled logic (business rules and the error cases → status codes), or an empty scaffold (501 bodies)?
6. **Migration:** apply it to the dev DB after review (yes/no)?

Echo back a compact spec (schema table + endpoint table) and get a yes before writing.

## Step 3: Build in order
Each layer depends on the one before it, so build in this order:
1. **Models** (`work-dao`): `model/<feature>_model_db.py`, `model/<feature>_model_domain.py`, `model/__init__.py`, and the `model_registry.py` import.
2. **DAO** (`work-dao`): `<feature>_dao.py` with the statements the endpoints need.
3. **Datasource** (`work-datastore`, only if needed): run `add-core` first if the core client is missing.
4. **Repository** (`work-repository`): `<feature>_repository.py`.
5. **Service** (`work-service`): `<feature>_service.py` with the methods (`request: Request`, Pydantic body → Pydantic response, starlette `HTTPException` + `status`) and `get_<feature>_service`.
6. **Router** (`work-service`): `<feature>_router.py`, registered in `app/app_router.py`.
7. **Migration** (`work-dao` step 3): autogenerate → review checklist → show the user → apply if approved.

Also create `app/<feature>/__init__.py` (and `__init__.py` in any new parent folders).

## Step 4: Verify
```bash
python -c "import main; print([p for p in sorted(main.app.openapi()['paths']) if '<prefix>' in p])"
```
If the DB and app are running (`docker compose up --build` applies migrations automatically through the `migrate` service), exercise the main endpoints with curl:
- create;
- get;
- list;
- one error case (404 or 409).

Fix failures before reporting.

## Step 5: Report
- **Files:** a tree of the files created and changed (marking what was pre-existing and kept).
- **Endpoints:** a table of `METHOD path → status`.
- **Migration:** the migration file, and whether it was applied.
- **Follow-ups:** what's left, e.g. scaffolded 501 methods to fill with `work-service`, or env keys to set.
