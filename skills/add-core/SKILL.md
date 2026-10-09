---
name: add-core
description: Add a reusable infrastructure client to app/core of a Tezca FastAPI project - AWS S3, Cloudflare R2, CloudFront (signed URLs, invalidations), Redis/cache, background job queue/worker/cron (ARQ), payments (Stripe, Mercado Pago, Conekta...), security (password hashing + JWT auth), AWS Cognito token verification, AWS Secrets Manager, email (SES/SendGrid...), a shared HTTP client, or any other third-party SDK. Installs/pins the libraries, adds settings + .env keys, writes an async class with a cached getter usable anywhere (services, repositories, datasources), wires shutdown in the lifespan and adds docker-compose services when useful. Use this whenever the user says things like "add S3", "connect redis", "I need payments", "add auth/JWT", "set up cognito", "read secrets from AWS", "configure email sending", "add <some SDK> to core" in a FastAPI project.
---

# add-core

Core classes are the project's adapters to the outside world. Each one is written once, configured from `Settings`, and reused everywhere through a cached getter. Feature code then never builds its own boto session or Redis pool.

**Shared conventions:** `${CLAUDE_PLUGIN_ROOT}/references/` (`../../references/` from this skill's base directory).
- `architecture.md`: where core sits in the call graph.
- `integrations/<name>.md`: a ready recipe per integration (requirements, settings, `.env` keys, class, getter, compose service).

| User says | Recipe | Core file |
|---|---|---|
| S3, bucket, file upload to AWS | `integrations/s3.md` | `app/core/s3.py` |
| R2, Cloudflare storage | `integrations/r2.md` (reuses the S3 class) | `app/core/r2.py` |
| CloudFront, CDN, signed URLs | `integrations/cloudfront.md` | `app/core/cloudfront.py` |
| Redis, cache, rate limit, locks | `integrations/redis.md` | `app/core/redis.py` |
| payments, Stripe, checkout | `integrations/stripe.md` | `app/core/payments.py` |
| security, JWT, passwords, login | `integrations/security_jwt.md` | `app/core/security.py` |
| Cognito | `integrations/cognito.md` | `app/core/cognito.py` |
| AWS secrets, secrets manager | `integrations/secrets_manager.md` | `app/core/secrets.py` + `config.py` source |
| email, SES, SendGrid | `integrations/ses.md` | `app/core/email.py` |
| HTTP client, 3rd-party API | `integrations/http_client.md` | `app/core/http_client.py` |
| background jobs, queue, worker, cron, scheduled tasks | `integrations/arq.md` (needs Redis) + `background_jobs.md` | `app/core/jobs.py` + `worker.py` |

## Workflow

1. **Confirm the project shape.** Check that `app/core/config.py` exists. If it doesn't, offer to run `start-fast-api` first, or adapt to wherever the project keeps its settings.
2. **Ask before writing.** If you were invoked from `start-fast-api`, its question round already covered these. Only ask about what is still unknown. Otherwise, ask only what you can't read from the project. Never assume credentials or provider choices.
   - Which integration(s), and for "payments"/"email": which provider.
   - Integration-specific details: bucket name; whether to use MinIO locally; signed CloudFront URLs or public ones; JWT access/refresh lifetimes; Cognito access or id tokens; Secrets Manager at startup, at runtime, or both; …
   - Whether to add a local docker-compose service (Redis, MinIO) when one applies.
3. **Check what exists.** If `app/core/<x>.py` already exists, show its public methods and ask whether to extend it, replace it or leave it. Don't duplicate settings keys that already exist; the AWS credentials are shared by S3/SES/CloudFront.
4. **Implement**, following the recipe:
   - **Requirements:** append exact pins to `requirements.txt` under `# Integrations`. Check for newer versions with `pip index versions <pkg>`. Keep packages that must agree (aioboto3/boto3) compatible.
   - **Settings:** add fields to `Settings` in `config.py` under a `# <Integration>` comment, below the "Integrations" marker. Add the same keys to `.env.example` (no real secrets) and to `.env.dev`/`.env.prod` if they exist.
   - **Core class:** write `app/core/<x>.py` with the class plus an `@lru_cache` getter (`get_<x>()`). The getter doubles as a FastAPI dependency. Raise errors from `app/core/exceptions.py` (`ExternalServiceError` subclasses for provider failures, `UnauthorizedError`/`ForbiddenError` for auth), never `HTTPException`.
   - **Lifespan:** if the client holds connections (Redis, the HTTP client), close it in the `main.py` lifespan after `yield`.
   - **Compose:** add the compose service + healthcheck + `depends_on` when the user wanted it.
     - **Hostnames:** `.env.*` files keep host-friendly values (`localhost:<port>`), so `uvicorn` and `alembic` work from the host. Containers reach the service by its compose name, so add that override (e.g. `REDIS_URL: redis://redis:6379/0`) under `x-app.environment` in `docker-compose.yml`, next to `DATABASE_HOST: db`.
     - **Port clashes:** check the host port is free (`lsof -i :<port>`) and change only the host side of the mapping if it isn't.
   - **Optional settings:** type them as `X | None = None`. The template's validator turns `KEY=` (empty) into `None`.
5. **Provider without a recipe** (e.g. Mercado Pago, Twilio, Firebase, OpenAI, Sentry): look up the provider's current official SDK docs (WebFetch / search). Then follow the same shape:
   - settings and env keys;
   - an async class (or the sync SDK wrapped with `starlette.concurrency.run_in_threadpool` if no async SDK exists);
   - a small named exception for provider failures, subclassing `ExternalServiceError` from `app/core/exceptions.py` (so it reaches clients as a 502 with its own `code`);
   - an `lru_cache` getter.

   Tell the user which docs you based it on.
6. **Verify:** `pip install -r requirements.txt`, then `python -c "from app.core.<x> import get_<x>"`, then `python -c "import main"`.
7. **Report:**
   - files changed;
   - new env keys the user must fill in;
   - a 3-line usage example, e.g. inside a service factory: `storage: Annotated[S3Storage, Depends(get_s3_storage)]`, or from a datasource.

## Usage rules to tell the user
Core classes may be called from **services, repositories and datasources**, never from routers directly; routers go through services. When a feature needs feature-specific logic around a core client (key layout, mapping a payload), that logic belongs in the feature's datasource (see `work-datastore`), not in core. Keeping core generic is what lets every feature reuse it.
