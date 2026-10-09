# AWS Secrets Manager (`app/core/secrets.py` + config source)

There are two complementary uses. Ask the user which ones they want.
1. **Configuration at startup:** load a JSON secret (e.g. database password, API keys) into `Settings`, so the rest of the app just reads `settings.database_password`. This is the common case.
2. **Runtime reads:** fetch secrets on demand, e.g. per-tenant credentials, with a small TTL cache.

**requirements.txt:** `boto3==1.43.110` (sync, used once at startup) and `aioboto3==15.5.0` (runtime). Check that the boto3 version is compatible with the aiobotocore pin; let pip resolve it, and if it conflicts, drop the explicit boto3 pin because aioboto3 brings a matching one.

## 1. Settings source (edit `app/core/config.py`)

```python
import json
import os

import boto3
from pydantic_settings import BaseSettings, PydanticBaseSettingsSource


class AwsSecretsManagerSource(PydanticBaseSettingsSource):
    """Loads a JSON secret (keys = setting names, any case) when AWS_SECRET_NAME is set."""

    def __init__(self, settings_cls: type[BaseSettings]):
        super().__init__(settings_cls)
        self._data: dict = {}
        secret_name = os.getenv("AWS_SECRET_NAME")
        if secret_name:
            client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1"))
            raw = client.get_secret_value(SecretId=secret_name)["SecretString"]
            self._data = {k.lower(): v for k, v in json.loads(raw).items()}

    def get_field_value(self, field, field_name):
        return self._data.get(field_name), field_name, False

    def __call__(self) -> dict:
        return {k: v for k, v in self._data.items() if k in self.settings_cls.model_fields}
```

Inside `class Settings`:
```python
    @classmethod
    def settings_customise_sources(cls, settings_cls, init_settings, env_settings, dotenv_settings, file_secret_settings):
        # priority: explicit init > real env vars > AWS secret > .env file > secrets dir
        return (init_settings, env_settings, AwsSecretsManagerSource(settings_cls), dotenv_settings, file_secret_settings)
```
`.env.example`:
```
AWS_SECRET_NAME=          # e.g. myapp/prod ; empty = disabled
```
In ECS/EKS, give the task role `secretsmanager:GetSecretValue` on that ARN. No keys are needed in env.

## 2. Runtime client (`app/core/secrets.py`)

```python
import json
import time
from functools import lru_cache
from typing import Any

import aioboto3

from app.core.config import get_settings


class SecretsManager:
    def __init__(self, region: str, ttl_seconds: int = 300):
        self._session = aioboto3.Session(region_name=region)
        self._ttl = ttl_seconds
        self._cache: dict[str, tuple[float, Any]] = {}

    async def get_secret(self, name: str) -> dict[str, Any] | str:
        cached = self._cache.get(name)
        if cached and cached[0] > time.monotonic():
            return cached[1]
        async with self._session.client("secretsmanager") as client:
            raw = (await client.get_secret_value(SecretId=name))["SecretString"]
        try:
            value: Any = json.loads(raw)
        except json.JSONDecodeError:
            value = raw
        self._cache[name] = (time.monotonic() + self._ttl, value)
        return value


@lru_cache
def get_secrets_manager() -> SecretsManager:
    return SecretsManager(get_settings().aws_region)
```
