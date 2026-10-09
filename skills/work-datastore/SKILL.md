---
name: work-datastore
description: Create or extend a feature datasource (<feature>_datasource.py) in a Tezca FastAPI project - the layer that reads/writes data that is NOT in our SQL database - object storage (S3/R2), cache (Redis), payment providers, email, or any third-party REST API (shipping, maps, CRM, AI, etc.), usually by wrapping an app/core client or the shared httpx client. Use whenever the user wants a feature to fetch from / push to an external API or service, "call the X API", "store files for this feature", "cache this", "integrate provider Y into feature Z", or explicitly asks for a datastore/datasource.
---

# work-datastore

A datasource adapts external data to one feature. It turns a generic core client, such as `S3Storage` or the shared `httpx.AsyncClient`, into feature-shaped methods like `upload_product_image()` or `get_shipping_rates()`. Only the feature's repository calls it.

**Read first:**
- `${CLAUDE_PLUGIN_ROOT}/references/datasource.md`: templates for both kinds (wrapping a core client, and a 3rd-party API) plus the rules.
- `architecture.md`: call graph.

`${CLAUDE_PLUGIN_ROOT}/references/` is `../../references/` from this skill's base directory.

## Step 1: Ask (don't infer)
Read the feature folder and `app/core/` first, then ask for what's missing:
- **Feature:** which one (path).
- **Source:**
  - (a) an existing core client: which one;
  - (b) a core client that doesn't exist yet;
  - (c) a 3rd-party HTTP API.
- **For a 3rd-party API:**
  - base URL and auth style (bearer, API key header, basic, OAuth client-credentials);
  - the endpoints to call, with request/response examples or a docs link (fetch the docs if given);
  - timeouts and retries;
  - which fields the feature needs back.
- **For storage, cache or payments:** key/naming layout, TTLs, content types, metadata.
- **Errors:** what counts as a failure, and whether any should be swallowed. The default is to raise a named exception.

## Step 2: Dependencies first
- **Missing core client (case b):** run the `add-core` workflow first (read `${CLAUDE_PLUGIN_ROOT}/skills/add-core/SKILL.md`), with the user's agreement.
- **3rd-party HTTP (case c):** make sure `app/core/http_client.py` exists (via add-core, `integrations/http_client.md`). Add the API's URL and key to `Settings` + `.env.example`; never hardcode them.

## Step 3: Write `<feature>_datasource.py`
Follow `datasource.md`:
- Class `<Feature>Datasource`, with its clients and settings injected through the constructor.
- Async methods that return plain data (dicts, dataclasses, or small Pydantic models describing the external payload), never ORM models.
- A named exception per failure mode (`<Provider>Error`), raised `from` the original error and logged with context. Never log secrets or full payloads containing personal data.
- If the file exists: list its methods, then add to them or ask before changing existing signatures.

## Step 4: Wire it
- **Repository:** the repository takes `datasource: <Feature>Datasource` in its constructor (`repository.md`). If no repository method uses it yet, ask which operation should, and add it via the `work-repository` workflow.
- **Service factory:** `get_<feature>_service` must now build the datasource with its dependency getters (`Depends(get_http_client)`, `get_s3_storage()`, …) and pass it to the repository.

## Step 5: Verify and report
- **Import check:** `python -c "import app.<feature>.<feature>_datasource"`.
- **Optional quick test:** for HTTP datasources, offer a small test using `httpx.MockTransport`.
- **Report:** methods added, settings/env keys to fill in, and which repository methods use them.
