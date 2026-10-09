---
name: work-dao
description: Create or change database tables in a Tezca FastAPI project - SQLAlchemy models (<feature>_model_db.py), the matching Pydantic domain models, the DAO statement builders (<feature>_dao.py), registration in app/core/model_registry.py, and an Alembic migration in sql/ that is generated, reviewed and applied. Use it whenever the user wants a new table, new/renamed/removed columns, indexes, constraints, enums, foreign keys or relationships, a new query in a DAO, or says things like "add a field to X", "create the orders table", "the users table needs...", "update the database", "make a migration" in a FastAPI/SQLAlchemy project.
---

# work-dao

Owns the data shape: tables (`model_db`), their API mirror (`model_domain`), the statements that read and write them (`dao`), and the migrations that put them in the database.

**Read first:** `${CLAUDE_PLUGIN_ROOT}/references/` (`../../references/` from this skill's base directory):
- `models.md`: model_db and model_domain rules, enum gotchas, `model/__init__.py`, registry;
- `dao.md`: the DAO builds statements only (the repository executes them);
- `migrations.md`: the Alembic workflow and the review checklist;
- `architecture.md`: naming and tree.

## Step 1: Understand the change (ask, don't infer)

Read what exists first: the feature's `model/`, `<feature>_dao.py`, `app/core/models.py`, `model_registry.py`, `sql/versions/`, and the DB driver in `config.py`.

Then ask the user for anything that isn't stated. Column details decide the migration, and a wrong guess means a second migration to undo it.
- **New table or alter existing.** Which feature folder (nested path?).
- **Per column:** name, type (string length, numeric precision, enum values, JSON…), nullable, default (Python or server), unique, indexed.
- **Keys:** primary key type (UUID default via `UUIDPkMixin`, or int). Timestamps (`TimestampMixin`) yes or no.
- **Relationships:** FKs (target table, `ondelete`), one-to-many / many-to-many (association table?), `back_populates` names.
- **For alters:** what happens to existing rows (backfill value for new NOT NULL columns; is it a rename or a drop+add).
- **DAO queries** the user already knows they need (filters, search, ordering). If they're not known, generate the standard set: `select_by_id`, `select_all` (filters + pagination), `count`, `insert`, `update_by_id`, `delete_by_id`, plus `exists_by_<unique field>`.

Summarize the planned schema as a compact table and confirm it before writing.

## Step 2: Write the code
1. **DB model:** `app/<feature>/model/<feature>_model_db.py`, following `models.md`. On the other side of a relationship, update that model too (with a `TYPE_CHECKING` import).
2. **Domain models:** `app/<feature>/model/<feature>_model_domain.py`. Add/update `CreateRequest`, `UpdateRequest`, `Response`, `ListQuery`, `ListResponse` so the API matches the new columns. Leave out internal or secret columns.
3. **Exports:** update `model/__init__.py`.
4. **DAO:** `app/<feature>/<feature>_dao.py`, following `dao.md`. Add statements for new columns and filters. When altering, update existing statements that select or filter on changed columns.
5. **Registry:** add `import app.<feature>.model.<feature>_model_db  # noqa: F401` to `app/core/model_registry.py` if it's missing.
6. **Downstream:** if a repository or service already uses changed columns, list the places (`grep -rn "<column>" app/`) and ask whether to update them now. The `work-repository` / `work-service` skills cover that work.

## Step 3: Migration
Follow `migrations.md`.
1. Make sure a database is reachable. Locally: `docker compose up -d db`, then `ENVIRONMENT=dev alembic upgrade head`, so the DB is at the current head before autogenerating.
   - If no DB can be reached, write the migration by hand, consistent with the models, and say so.
2. Run `ENVIRONMENT=dev alembic revision --autogenerate -m "<imperative summary>"`.
3. Open the generated file and run the **review checklist**: renames, enum create/drop, NOT NULL backfills, downgrade correctness. Fix it by hand where needed.
4. Show the user the `upgrade()`/`downgrade()` body and **ask** before running `ENVIRONMENT=dev alembic upgrade head`. Mention that `docker compose up --build` also applies it through the `migrate` service.
5. Optional sanity check: `alembic downgrade -1 && alembic upgrade head` on a dev database.

## Step 4: Test
- **DAO tests:** add or extend `tests/<feature path>/test_<feature>_dao.py` with one test per new or changed statement (`testing.md`).
- **Run:** `pytest tests/<feature path> -q`. The test run applies all migrations to a fresh database, so a broken migration fails here too.
- **Lint and types:** `make lint typecheck`.

## Step 5: Report
List:
- the model/DAO/domain files touched;
- the migration file and whether it was applied;
- any downstream code that still needs updating.

If the table is brand new and has no repository/service/router yet, suggest `work-repository` → `work-service`, or `add-new-feature` to do all of it at once.
