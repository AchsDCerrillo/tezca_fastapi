---
name: work-service
description: Implement business logic and expose it as an endpoint in a Tezca FastAPI project - write or extend <feature>_service.py (methods that take the FastAPI Request plus a Pydantic request model, orchestrate one or more repositories and core classes, raise domain exceptions (NotFoundError, ConflictError, BusinessRuleError...) that map to a standard JSON error body, and return Pydantic response models), its build_/get_<feature>_service factories, unit + API tests, and the matching route in <feature>_router.py registered in app/app_router.py. Use whenever the user describes a use case or scenario ("when a user checks out...", "create an endpoint that...", "add business rule X", "expose Y over the API", "add a POST /orders"), names repositories/methods a service should call, or asks for a service or route.
---

# work-service

The service is where a use case lives. It validates rules that need data, coordinates repositories and core classes, raises domain exceptions, and returns Pydantic models. The router just exposes it, and the error handlers turn exceptions into HTTP responses.

**Read first:** in `${CLAUDE_PLUGIN_ROOT}/references/` (`../../references/` from this skill's base directory):
- `service.md`: signature convention, template, the two factories, the domain-exception table;
- `testing.md`: service unit tests and API tests;
- `router.md`: route template + registration in `app/app_router.py`;
- `models.md`: request/response models;
- `architecture.md`: call graph. The service uses repositories and core classes only, never DAOs or datasources.

## Project conventions for service methods
- **Signature:** `async def <action>(self, request: Request, body: <Pydantic model>, ...path ids) -> <Pydantic response>`.
  - `Request` is `from fastapi import Request`, the incoming request (`request.state` carries request id / current user).
  - Body-less GETs take a query model or the path id instead of a body.
- **Errors:** raise domain exceptions from `app/core/exceptions.py`, e.g. `raise NotFoundError("Order not found")` or `raise BusinessRuleError("Not enough stock", code="insufficient_stock")`. `app/core/error_handlers.py` turns them into `{"detail", "code", "request_id"}` with the right status. Don't raise `HTTPException` in services; keeping HTTP out of them lets jobs and scripts reuse them (`background_jobs.md`).
- **Return value:** a Pydantic model built with `Model.model_validate(orm)`, never an ORM object.

## Step 1: Ask (don't infer)
Read the feature folder, the existing service/router, and the repositories the user mentions. Then ask for what's missing, in one grouped message:
1. **Scenario:** steps, business rules, and what must happen atomically.
2. **Building blocks:** which repositories (from which features) and which of their methods, and which core classes (payments, email, cache…). List the methods that exist so the user can pick.
3. **Endpoint:**
   - HTTP method and path;
   - router file (default: `<feature>_router.py` in the same feature folder, created if missing);
   - success status code;
   - auth requirement (e.g. `Depends(get_current_token)` if `app/core/security.py` exists).
4. **Models:** the request model (fields + validation) and the response model. Reuse existing domain models when they fit.
5. **Error cases:** each failure condition → domain exception (status), `code` and message. Offer the table in `service.md` as defaults.
6. **Reuse outside HTTP:** will this logic also run from a background job or script? If so, read `background_jobs.md`: the method takes `request: Request | None = None` and must not rely on it.

If the user only wants an **empty scaffold**, generate the class, factories, routes and models, with method bodies that `raise NotImplementedAppError()` (501, see `service.md`).

## Step 2: Fill gaps in lower layers
For every repository method the scenario needs that doesn't exist, create it through the `work-repository` workflow (`${CLAUDE_PLUGIN_ROOT}/skills/work-repository/SKILL.md`). That workflow in turn adds any missing DAO statements, or runs `work-dao` if tables or columns are missing. Confirm each new method's contract with the user as part of Step 1, rather than discovering it halfway through.

## Step 3: Write the code
1. **Domain models:** add new request/response/query models to `model/<feature>_model_domain.py` and export them from `model/__init__.py`.
2. **Service:** in `<feature>_service.py`, add methods to the class (create the class if missing).
   - **Constructor:** receives every repository and core client the class needs.
   - **Logic:** the business rules, raising domain exceptions. Datasource errors already subclass `ExternalServiceError` (502); catch them only to add a fallback. Wrap unique-constraint writes in `except IntegrityError` → `ConflictError`.
   - **Logging:** `logger.info(...)` for notable state changes, without personal data or secrets.
3. **Factories:** update `build_<feature>_service(session, ...)`. It builds every repository on the **same** session, including repositories from other features, plus core clients. `get_<feature>_service` only resolves the `Depends(...)` and calls it.
4. **Router:** add the endpoint to `<feature>_router.py` (template in `router.md`):
   - `request: Request`, the body/query model, path ids, `service: Annotated[<F>Service, Depends(get_<f>_service)]`;
   - `response_model` and `status_code`;
   - one line: `return await service.<action>(request, ...)`.
5. **Registration:** if the router file is new, register it in `app/app_router.py` (import alias + `include_router`). Ask about the URL prefix when the feature is nested.
6. **Tests:** follow `testing.md` (the `work-tests` workflow).
   - In `test_<feature>_service.py`, one unit test per rule and per raised exception, using `AsyncMock(spec=...)` repositories.
   - In `test_<feature>_api.py`, the happy path plus each error status, asserting the body's `code`.

## Step 4: Verify
- **Format, lint, types and tests:** `make format && make lint typecheck`, then `pytest tests/<feature path> -q`. Fix failures before reporting.
- **Import check:** `python -c "import main"`.
- **Route check:** `python -c "import main; print(sorted(main.app.openapi()['paths']))"` (use the OpenAPI paths: on recent FastAPI versions, `app.routes` holds included routers rather than flattened routes). The new route must appear.
- **Runtime check:** if the app and DB are running, curl the endpoint once for the happy path and once for one error case, and show the responses.

## Step 5: Report
- the endpoint (`METHOD /full/path` → status);
- the service method and the repositories/core classes it uses;
- new or changed models;
- lower-layer methods that were created along the way;
- tests added, and the result of the run.
