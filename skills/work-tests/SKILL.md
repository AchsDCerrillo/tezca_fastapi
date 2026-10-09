---
name: work-tests
description: Write or extend tests for a Tezca FastAPI project - DAO statement tests (no DB), service unit tests with mocked repositories (business rules and domain exceptions), and API tests against a real Postgres (testcontainers or CI service) through httpx; also sets up the test harness (tests/conftest.py, pytest config, requirements-dev) when it's missing and fixes failing tests. Use whenever the user asks to test a feature/endpoint/service, "add tests", "cover this", "why is this test failing", wants coverage before a refactor, or after building a feature without tests.
---

# work-tests

Tests are how the plugin's promises are kept: the DAO builds the right SQL, the service enforces each rule with the right domain exception, and the API returns the right status and error body against the real database and migrations.

**Read first:** in `${CLAUDE_PLUGIN_ROOT}/references/` (`../../references/` from this skill's base directory):
- `testing.md`: the three levels, the harness, full examples;
- `service.md`: the error table (which exception means which status/code);
- `architecture.md`: test tree.

## Step 1: Check the harness
Check that the harness pieces exist:
- `tests/conftest.py`;
- `[tool.pytest.ini_options]` in `pyproject.toml` (`asyncio_mode = "auto"`, `pythonpath = ["."]`);
- `requirements-dev.txt` with pytest, pytest-asyncio, httpx and testcontainers.

If any is missing, copy it from `${CLAUDE_PLUGIN_ROOT}/skills/start-fast-api/assets/templates/` (`tests/conftest.py`, `pyproject.toml`, `requirements-dev.txt`), merging into existing files instead of overwriting them. Adapt `conftest.py` if the database isn't Postgres (see `testing.md`). Run `pip install -r requirements-dev.txt`.

## Step 2: Decide what to test (ask only what the code can't tell you)
Read the feature's DAO, repository, service, router and domain models. From them, derive:
- **DAO tests:** one per `select_*` with filters (assert `WHERE`/`ORDER BY`/`LIMIT`), plus updates/deletes targeting the right rows.
- **Service tests:** one per business rule and per raised exception (`NotFoundError`, `ConflictError`, `BusinessRuleError` with its `code`…), plus the happy path's returned model.
- **API tests:** per endpoint, the happy path and each documented error status. Add one validation-error test per create/update model, and auth (401/403) when the route is protected.

Show the user the planned test list grouped by file. Ask only about behavior the code leaves ambiguous; for example, whether an expected edge case is intentionally unhandled. Don't encode current bugs as expected behavior: if the code looks wrong, say so and ask.

## Step 3: Write the tests
- **Location:** `tests/<feature path>/test_<feature>_{dao,service,api}.py`, plus `__init__.py` in each new folder.
- **Shape:** follow the examples in `testing.md`:
  - `AsyncMock(spec=Repository)` for service tests, with `SimpleNamespace` rows;
  - the `client` fixture for API tests, with `pytestmark = pytest.mark.integration`;
  - small `create_<entity>` helpers instead of fixtures that hide data.
- **Assertions:** assert the status **and** the body's `code`, because clients rely on the code.
- **External services:** override their dependency getters, or use `httpx.MockTransport`. Never call real providers.
- **Style:** keep tests independent and readable (arrange / act / assert), with no shared mutable state.

## Step 4: Run and fix
```bash
pytest tests/<feature path> -q          # Docker running, or TEST_DATABASE_* set
make lint typecheck                     # tests are linted too
```
- **Failing test:** decide whether the test or the code is wrong. Fix test mistakes directly. For code bugs, show the failure and propose the fix; apply it if the user agrees.
- **Docker unavailable:** run `TEST_SKIP_DB=1 pytest -m "not integration"` for the unit tests, and say the API tests still need a database.

## Step 5: Report
- the number of tests per level, and the run result (pass/fail counts, duration);
- bugs found in the code, if any;
- remaining gaps (e.g. auth not covered because no auth dependency exists yet).
