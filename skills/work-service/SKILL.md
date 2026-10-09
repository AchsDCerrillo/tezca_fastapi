---
name: work-service
description: Implement business logic and expose it as an endpoint in a Tezca FastAPI project - write or extend <feature>_service.py (methods that take the FastAPI Request plus a Pydantic request model, orchestrate one or more repositories and core classes, raise starlette HTTPException with starlette status codes, and return Pydantic response models), its get_<feature>_service dependency factory, and the matching route in <feature>_router.py registered in app/app_router.py. Use whenever the user describes a use case or scenario ("when a user checks out...", "create an endpoint that...", "add business rule X", "expose Y over the API", "add a POST /orders"), names repositories/methods a service should call, or asks for a service or route.
---

# work-service

The service is where a use case lives. It validates rules that need data, coordinates repositories and core classes, maps errors to HTTP statuses, and returns Pydantic models. The router just exposes it.

**Read first:** in `${CLAUDE_PLUGIN_ROOT}/references/` (`../../references/` from this skill's base directory):
- `service.md`: signature convention, template, factory, error mapping;
- `router.md`: route template + registration in `app/app_router.py`;
- `models.md`: request/response models;
- `architecture.md`: call graph. The service uses repositories and core classes only, never DAOs or datasources.

## Project conventions for service methods
- **Signature:** `async def <action>(self, request: Request, body: <Pydantic model>, ...path ids) -> <Pydantic response>`.
  - `Request` is `from fastapi import Request`, the incoming request (`request.state` carries request id / current user).
  - Body-less GETs take a query model or the path id instead of a body.
- **Errors:** `from starlette.exceptions import HTTPException` and `from starlette import status`, e.g. `raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")`.
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
5. **Error cases:** each failure condition → status code + detail message (offer the table in `service.md` as defaults).

If the user only wants an **empty scaffold**, generate the class, factory, routes and models, with method bodies raising `501 Not Implemented` (see `service.md`).

## Step 2: Fill gaps in lower layers
For every repository method the scenario needs that doesn't exist, create it through the `work-repository` workflow (`${CLAUDE_PLUGIN_ROOT}/skills/work-repository/SKILL.md`). That workflow in turn adds any missing DAO statements, or runs `work-dao` if tables or columns are missing. Confirm each new method's contract with the user as part of Step 1, rather than discovering it halfway through.

## Step 3: Write the code
1. **Domain models:** add new request/response/query models to `model/<feature>_model_domain.py` and export them from `model/__init__.py`.
2. **Service:** in `<feature>_service.py`, add methods to the class (create the class if missing).
   - **Constructor:** receives every repository and core client the class needs.
   - **Logic:** the business rules, using `HTTPException` with `status.*`. Map datasource and domain exceptions (`except ShippingRateError as exc: raise HTTPException(status.HTTP_502_BAD_GATEWAY, ...) from exc`).
   - **Logging:** `logger.info(...)` for notable state changes, without personal data or secrets.
3. **Factory:** update `get_<feature>_service` so it builds every repository, sharing the **same** session, and injects core clients through their getters. Repositories from other features are built here too.
4. **Router:** add the endpoint to `<feature>_router.py` (template in `router.md`):
   - `request: Request`, the body/query model, path ids, `service: Annotated[<F>Service, Depends(get_<f>_service)]`;
   - `response_model` and `status_code`;
   - one line: `return await service.<action>(request, ...)`.
5. **Registration:** if the router file is new, register it in `app/app_router.py` (import alias + `include_router`). Ask about the URL prefix when the feature is nested.

## Step 4: Verify
- **Import check:** `python -c "import main"`.
- **Route check:** `python -c "import main; print(sorted(main.app.openapi()['paths']))"` (use the OpenAPI paths: on recent FastAPI versions, `app.routes` holds included routers rather than flattened routes). The new route must appear.
- **Runtime check:** if the app and DB are running, curl the endpoint once for the happy path and once for one error case, and show the responses.

## Step 5: Report
- the endpoint (`METHOD /full/path` → status);
- the service method and the repositories/core classes it uses;
- new or changed models;
- lower-layer methods that were created along the way.
