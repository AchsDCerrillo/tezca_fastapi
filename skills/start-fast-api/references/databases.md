# Database variants

Use these values to fill the `{{...}}` placeholders in the templates.

| Placeholder | PostgreSQL (default) | MySQL / MariaDB | SQLite (dev/prototype only) |
|---|---|---|---|
| `DATABASE_LABEL` | PostgreSQL 17 | MySQL 8 | SQLite |
| `DATABASE_DRIVER` | `postgresql+asyncpg` | `mysql+aiomysql` | `sqlite+aiosqlite` |
| `DATABASE_DRIVER_PACKAGE` | `asyncpg==0.32.0` | `aiomysql==0.3.2` + `cryptography` (needed for caching_sha2 auth) | `aiosqlite==0.22.1` |
| `DATABASE_PORT` (host) | `5432` | `3306` | `0` |
| `DB_CONTAINER_PORT` | `5432` | `3306` | – |
| `DATABASE_USER` / `DATABASE_PASSWORD` defaults | `postgres` / `postgres` | `app` / `app` | – |
| `DATABASE_NAME` | project slug (snake_case) | project slug | `./<slug>.db` |

Pins were current when the plugin was written. Before writing `requirements.txt`, check for newer versions with `pip index versions <pkg>`, and keep pins exact.

## docker-compose `db` service

**PostgreSQL:** the block in the template.

**MySQL:**
```yaml
  db:
    # Database service (MySQL 8)
    image: mysql:8.4
    environment:
      MYSQL_DATABASE: {{DATABASE_NAME}}
      MYSQL_USER: {{DATABASE_USER}}
      MYSQL_PASSWORD: {{DATABASE_PASSWORD}}
      MYSQL_ROOT_PASSWORD: {{DATABASE_PASSWORD}}
    ports:
      - "{{DATABASE_PORT}}:3306"
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "{{DATABASE_USER}}", "-p{{DATABASE_PASSWORD}}"]
      interval: 5s
      timeout: 5s
      retries: 20
```
MySQL does not support `RETURNING`; tell the user, and note it so DAO/repository work follows the MySQL path in `references/dao.md`.

**SQLite:**
- Remove the `db` service, the `db_data` volume and the `depends_on: db` entries.
- In `x-app`, drop `DATABASE_HOST`/`DATABASE_PORT` and mount a volume for the file, e.g. `volumes: ["./data:/app/data"]` with `DATABASE_NAME=./data/<slug>.db`.

## Other databases
For SQL Server, Oracle or CockroachDB:
- find the async SQLAlchemy driver (WebFetch the SQLAlchemy dialect docs);
- fill the same placeholders;
- tell the user that this combination is not covered by the plugin's tested defaults.
