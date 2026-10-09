# Tezca FastAPI architecture

This is the single source of truth for how a Tezca FastAPI project is laid out.
Every skill in this plugin reads it, so a project built by `start-fast-api`
and grown by the other skills always looks the same.

## Table of contents
1. Project tree
2. Layers and the call graph
3. Naming conventions
4. Code style
5. Detecting an existing project

## 1. Project tree

```
<project>/
├── main.py                    # FastAPI app: lifespan, logging, middleware, includes app.app_router.router
├── alembic.ini                # script_location = sql
├── requirements.txt           # pinned, pip
├── Dockerfile
├── docker-compose.yml
├── .env.example               # every key, no secrets (committed)
├── .env.dev / .env.prod       # real values (git-ignored)
├── README.md
├── scripts/entrypoint.sh      # optional migrations, then uvicorn
├── sql/                       # Alembic environment = every database change lives here
│   ├── env.py
│   ├── script.py.mako
│   └── versions/
└── app/
    ├── __init__.py
    ├── app_router.py          # the ONLY place feature routers are registered
    ├── core/
    │   ├── __init__.py
    │   ├── config.py          # Settings (pydantic-settings) + get_settings()
    │   ├── database.py        # async engine, session factory, get_session
    │   ├── models.py          # Base, naming convention, mixins
    │   ├── model_registry.py  # imports every *_model_db module (Alembic + relationships)
    │   ├── logging.py         # dictConfig, console in dev / JSON in prod
    │   ├── middleware.py      # request id + access log
    │   └── <integration>.py   # s3.py, redis.py, security.py, ... (added by add-core)
    └── <feature>/             # may be nested: app/project/api_key/
        ├── __init__.py
        ├── model/
        │   ├── __init__.py
        │   ├── <feature>_model_db.py      # SQLAlchemy models
        │   └── <feature>_model_domain.py  # Pydantic request/response models
        ├── <feature>_dao.py
        ├── <feature>_datasource.py        # optional
        ├── <feature>_repository.py
        ├── <feature>_service.py
        └── <feature>_router.py
```

## 2. Layers and the call graph

```
router ──► service ──► repository ──► dao ──► model_db
                 │             ├────► datasource ──► core / 3rd-party APIs
                 └──► core     └────► core
```

| Layer | Job | Returns | May call |
|---|---|---|---|
| `model_db` | SQLAlchemy tables | – | `app.core.models` |
| `model_domain` | Pydantic validation of input and shape of output | – | – |
| `dao` | **Builds** SQLAlchemy statements (`select`, `insert`, `update`, `delete`). It never touches a session, so it is pure and trivially testable. | `Select`, `Insert`, `Update`, `Delete` | model_db |
| `datasource` | Everything that is not our database: S3, Redis, payments, 3rd-party HTTP APIs | plain Python / dicts / dataclasses | core clients, httpx |
| `repository` | **Executes** DAO statements on the `AsyncSession` and combines them with datasource calls into whole operations. Owns `flush`/`refresh`, never `commit` (the session dependency commits). | SQLAlchemy model instances (or `None`, lists, counts) | dao, datasource, core |
| `service` | Business logic, validation that needs data, orchestration of many repositories, mapping ORM → Pydantic, raising HTTP errors | Pydantic `*Response` models | repositories, core classes. **Never** a dao or datasource. |
| `router` | HTTP mapping only: path, method, status code, response_model, dependency injection | whatever the service returns | the service of its feature (or another feature's service) |

The rules exist so that each layer can change without rippling. A router that
reaches into a repository, or a service that builds SQL, breaks that guarantee.
If a request seems to need a shortcut, add the missing method to the right
layer instead.

## 3. Naming conventions

- Feature folder: `snake_case`, singular (`product`, `api_key`). Nested features follow the URL hierarchy (`app/project/api_key`).
- Files: `<feature>_dao.py`, `<feature>_repository.py`, ... where `<feature>` is the leaf folder name.
- Classes: `PascalCase` + layer suffix: `ProductDao`, `ProductDatasource`, `ProductRepository`, `ProductService`.
- SQLAlchemy model: the entity name (`Product`). Table: plural snake_case (`products`).
- Pydantic models: `ProductCreateRequest`, `ProductUpdateRequest`, `ProductResponse`, `ProductListResponse`, plus any `Product<Action>Request` needed.
- Router module variable: always `router`. Import it with an alias: `from app.product.product_router import router as product_router`.
- Service factory: `get_product_service` at the bottom of `product_service.py`.
- Imports are absolute (`from app.product.model.product_model_db import Product`).

## 4. Code style

- Python 3.12+ syntax: `X | None`, `list[str]`, `dict[str, Any]`.
- Fully async: `async def` everywhere that touches I/O; `AsyncSession`; async clients (aioboto3, redis.asyncio, httpx.AsyncClient).
- Type-hint every parameter and return value.
- Every model has `__repr__`.
- Use `logging.getLogger(__name__)` per module; never `print`.
- Use `datetime.now(timezone.utc)`, never `datetime.utcnow()` (deprecated).
- Put imports at the top of the module, not inside functions. The exception is cycle-breaking `TYPE_CHECKING` imports.
- Keep comments short and only where the *why* is not obvious.

## 5. Detecting an existing project

Before generating anything, look at what is already there:

```bash
ls app app/core sql 2>/dev/null; test -f app/app_router.py && echo has_app_router
grep -rn "DeclarativeBase" app | head      # where Base lives
grep -rln "APIRouter" app | head            # existing routers
```

If the project deviates from this architecture (e.g. `Base` declared inside a
feature model, routers registered in `main.py`, no `model_domain` files), tell
the user what you found and ask whether to adapt the project or to follow its
existing pattern for this change. Don't silently refactor code the user didn't
ask about.
