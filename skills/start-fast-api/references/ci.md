# CI/CD (GitHub Actions)

There are two workflows. The test gate is defined once, in `ci.yml`, and `release.yml` calls it, so a release can never publish an image that skips lint or tests.

| Workflow | Trigger | Does |
|---|---|---|
| `.github/workflows/ci.yml` | PRs, pushes to `main`, and `workflow_call` | `ruff check` + `ruff format --check` + `mypy` · `pytest` against a Postgres service (runs the Alembic migrations) · a Docker build without push |
| `.github/workflows/release.yml` | GitHub release **published** | ① calls `ci.yml` → ② builds and pushes `IMAGE:<release tag>` plus a channel tag (`latest` for prod, `dev` for dev) with build-arg `APP_ENV` → ③ rewrites the `# release-image` line in `docker-compose.<env>.yml` and commits it to the default branch |

**Environment from tag:**
- A tag containing `-dev` or `-st` (e.g. `v1.4.0-dev.1`, `v1.4.0-st`) → `APP_ENV=dev`, updates `docker-compose.dev.yml`.
- Anything else (e.g. `v1.4.0`) → `APP_ENV=prod`, updates `docker-compose.prod.yml`.

If the user wants other environments (e.g. `-qa`), extend the `Derive environment from tag` step and add a matching `docker-compose.<env>.yml`.

**Trigger:** `published` is used instead of `created` because `created` also fires when a *draft* is saved, which would ship unreleased code. Mention this if the user's old pipeline used `created`.

## Registry login (`# {{REGISTRY_LOGIN_STEPS}}` in release.yml)
Replace that comment line with the block for the chosen registry, indented to match the other steps (6 spaces). Set `IMAGE_REPOSITORY` in `release.yml`, `docker-compose.prod.yml`, `docker-compose.dev.yml` and the README.

### Docker Hub
```yaml
      - name: Log in to Docker Hub
        uses: docker/login-action@v4
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
```
- **Secrets:** `DOCKERHUB_USERNAME`, plus `DOCKERHUB_TOKEN` (a Docker Hub access token with Read & Write).
- **`IMAGE_REPOSITORY`:** `<user-or-org>/<slug>`.

### GHCR (no extra secrets: uses the workflow token)
```yaml
      - name: Log in to GHCR
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
```
- **`IMAGE_REPOSITORY`:** `ghcr.io/<owner>/<slug>`, all lowercase.
- **Private packages:** a package on GHCR is private by default. The server that pulls it needs `docker login ghcr.io` with a PAT that has `read:packages`.

### AWS ECR (OIDC, no long-lived keys)
```yaml
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: <region>
      - name: Log in to ECR
        uses: aws-actions/amazon-ecr-login@v2
```
- **IAM role:** create one trusted by GitHub's OIDC provider for this repository, with ECR push permissions, and store its ARN as `AWS_ROLE_ARN`.
- **Repository:** create it once with `aws ecr create-repository --repository-name <slug>`.
- **`IMAGE_REPOSITORY`:** `<account>.dkr.ecr.<region>.amazonaws.com/<slug>`. The workflow already grants `id-token: write`.

### Other registries (Azure ACR, Google Artifact Registry, Harbor, self-hosted…)
```yaml
      - name: Log in to registry
        uses: docker/login-action@v4
        with:
          registry: <registry-host>
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}
```

## Compose update and branch protection
The `update-compose` job commits to the default branch with the workflow token (`contents: write`). The commit message carries `[skip ci]`, so it doesn't loop CI.

**Protected default branch:** pushes from the workflow token are rejected if the default branch requires PRs or reviews. Tell the user to either:
- create a fine-grained PAT, or a GitHub App token, with `contents: write` on the repo, and store it as the `RELEASE_BOT_TOKEN` secret (the workflow uses it automatically when present), and allow it to bypass the rule; or
- change the job to open a PR instead of pushing (e.g. `peter-evans/create-pull-request`). Only do this if they ask.

**`# release-image` marker:** only `image:` lines ending with `# release-image` are rewritten, so other images in the compose file (redis, worker sidecars) are left alone. If a worker service uses the same image, it shares the `x-app` anchor and picks up the tag too.

## Database service per engine (ci.yml `test` job)
- **PostgreSQL:** the template as is.
- **MySQL:**
  - Replace the service with `mysql:8.4`; env `MYSQL_DATABASE/MYSQL_USER/MYSQL_PASSWORD/MYSQL_ROOT_PASSWORD` = `test`; port `3306:3306`; health command `mysqladmin ping -h localhost -utest -ptest`.
  - Set `TEST_DATABASE_PORT: "3306"`.
- **SQLite:** delete `services:` and the `TEST_DATABASE_*` env vars.

## User checklist (put it in the final report and the README)
1. Add the registry secrets (none for GHCR).
2. If `main` is protected, add `RELEASE_BOT_TOKEN`.
3. To ship: `gh release create v0.1.0 --generate-notes` (prod), or `gh release create v0.1.0-dev.1 --prerelease --generate-notes` (dev).
4. On the server: `git pull`, then `docker compose -f docker-compose.<env>.yml pull && docker compose -f docker-compose.<env>.yml up -d`.
