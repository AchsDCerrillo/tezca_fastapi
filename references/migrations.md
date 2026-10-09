# Database migrations with Alembic (`sql/` folder)

Every schema change goes through Alembic. The environment lives in `sql/`, with `alembic.ini` at the project root (`script_location = sql`). Alembic compares the SQLAlchemy models (imported through `app/core/model_registry.py`) with the live database and writes the migration for you.

Don't use `Base.metadata.create_all()` at startup. It can create tables but never alters them, and it fights with Alembic's version tracking.

## Everyday workflow

```bash
# 1. change/add models in app/<feature>/model/<feature>_model_db.py
# 2. make sure the module is imported in app/core/model_registry.py
# 3. generate the migration (needs a reachable database with the current schema)
alembic revision --autogenerate -m "create products table"
# 4. REVIEW the generated file in sql/versions/ (see checklist below)
# 5. apply it
alembic upgrade head
```

Other useful commands:

```bash
alembic current                 # revision the DB is at
alembic history --verbose       # all revisions
alembic downgrade -1            # undo the last migration
alembic upgrade head --sql      # print the SQL instead of running it (offline mode)
```

With docker compose:

```bash
docker compose up -d db
docker compose run --rm api alembic revision --autogenerate -m "..."
docker compose run --rm api alembic upgrade head
```

Running locally against the compose database: the `.env.dev` `DATABASE_HOST` must be `localhost` (not `db`). Run with `ENVIRONMENT=dev alembic ...`.

## Review checklist for each generated migration
Autogenerate is good, but not perfect. Before applying a migration, open it and check:
- [ ] **Empty or missing tables:** an empty `upgrade()` or a missing table means a model module isn't imported in `model_registry.py`.
- [ ] **Renames:** a column or table rename shows up as **drop + add**, which loses data. Rewrite it with `op.alter_column(..., new_column_name=...)` / `op.rename_table`.
- [ ] **Enums (Postgres):** new enum types are created automatically, but `downgrade()` must drop them:
  `sa.Enum(name="product_status").drop(op.get_bind(), checkfirst=True)`.
  To add a value to an existing enum, write it by hand: `op.execute("ALTER TYPE product_status ADD VALUE IF NOT EXISTS 'draft'")`.
- [ ] **NOT NULL on a table with data:** this needs a `server_default`, or a three-step migration (add nullable → backfill with `op.execute` → set NOT NULL).
- [ ] **Server defaults and type changes:** autogenerate may not detect them. `compare_type=True` and `compare_server_default=True` are enabled in `sql/env.py`, but still double-check.
- [ ] **Downgrade:** `downgrade()` really reverses `upgrade()`.

Show the user the migration and ask before running `alembic upgrade head`. It changes a real database, and an environment other than local may hold real data.

## First migration of a new project
After `start-fast-api` there are no models yet. The first feature (`add-new-feature` / `work-dao`) creates the first revision. Generating an empty "init" revision is optional.

## Adopting Alembic in a project whose database already exists
If the database was created by hand (e.g. a `db_script.sql`):
1. Make sure the models match the existing schema.
2. `alembic revision --autogenerate -m "baseline"`. Inspect it: ideally it is empty. If not, the models don't match the database; fix the models, or keep the differences as real changes.
3. `alembic stamp head` marks the database as being at the baseline without running it.
4. From now on, use the normal workflow.

## Data migrations
Data migrations are allowed inside a revision with `op.execute(sa.text("UPDATE ..."))` or `op.bulk_insert`. Keep them idempotent, and never import application models into a migration: they change over time, but the migration must not.
