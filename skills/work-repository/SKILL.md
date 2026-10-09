---
name: work-repository
description: Create a repository from scratch or add/update methods in an existing one (<feature>_repository.py) in a Tezca FastAPI project - the layer that executes DAO statements on the AsyncSession, combines them with datasource or core calls into complete operations, and returns SQLAlchemy models. Use whenever the user asks for a repository, a new data-access method ("get orders by customer", "soft delete", "paginate products", "create X and upload its file"), or wants database operations implemented for a feature, even if they only describe the query they need.
---

# work-repository

All database work happens here. The repository runs the statements the DAO builds, adds datasource and core calls when an operation spans systems, and hands back SQLAlchemy models. HTTP concerns stay out of it.

**Read first:** in `${CLAUDE_PLUGIN_ROOT}/references/` (`../../references/` from this skill's base directory):
- `repository.md` (template + rules);
- `dao.md` (because missing statements get added there);
- `architecture.md`.

## Step 1: Ask, don't infer
Read the feature's `model/`, `<feature>_dao.py`, `<feature>_datasource.py` (if any) and the existing `<feature>_repository.py` first. Then confirm with the user:
- **New or existing:** a brand-new repository, or methods to add or change in an existing one. For an existing one, list its current methods.
- **Per method:**
  - name;
  - inputs (types, optional filters);
  - output (single model / `None`, list, count, bool);
  - eager-loaded relationships;
  - ordering and pagination.
- **Building blocks:** which DAO statements, datasource methods or core classes each method uses. If an operation spans the DB and an external system (e.g. create row + upload file), ask about the failure order: what happens to the row if the upload fails?
- **New repository with no stated method list:** propose the standard CRUD set (`get_by_id`, `get_all`, `count`, `create`, `update`, `delete`, `exists_by_<unique>`) and let the user trim or extend it.

Don't invent business rules (permissions, status transitions). They belong in the service, and the user should state them there.

## Step 2: Make sure the lower layers exist
- **DAO:** if a method needs a statement the DAO doesn't have, add it to `<feature>_dao.py`, following `dao.md` (the work-dao conventions). If the **table or columns** don't exist yet, stop and run the `work-dao` workflow first (`${CLAUDE_PLUGIN_ROOT}/skills/work-dao/SKILL.md`), because it handles the migration.
- **Datasource:** if a datasource or core client is needed and missing, use `work-datastore` / `add-core` first.

## Step 3: Write `<feature>_repository.py`
Follow `repository.md`:
- **Constructor:** `__init__(self, session: AsyncSession, dao: <F>Dao, datasource: <F>Datasource | None = None, ...)`.
- **Execution:** execute through `self.session.scalars(...)` / `.scalar(...)` / `.execute(...)`. Return ORM instances, `Sequence[Model]`, `int` or `bool`.
- **Transactions:** `flush()` when generated values are needed mid-operation; never `commit()`.
- **Errors:** "not found" is `None` / `False`, never an HTTP exception.
- **Inputs:** `dict[str, Any]` (from `model_dump(exclude_unset=True)` in the service), or explicit keyword arguments.
- **MySQL** (check `DATABASE_DRIVER`): use the no-RETURNING path described in `dao.md` / `repository.md`.
- **Existing methods:** keep their signatures stable. If a change would break callers, list them (`grep -rn "repository.<method>" app/`) and ask first.

## Step 4: Wire and verify
- **Factory:** make sure `build_<feature>_service` (if it exists) constructs the repository with the new constructor arguments.
- **Import check:** `python -c "import app.<feature>.<feature>_repository"`.
- **Tests:** new repository methods are covered through the API tests (they run real SQL); new DAO statements get a DAO test (`testing.md`). Run `pytest tests/<feature path> -q`.
- **Report:** methods added/changed, DAO statements added, and which service methods could use them. Suggest `work-service` to expose them.
