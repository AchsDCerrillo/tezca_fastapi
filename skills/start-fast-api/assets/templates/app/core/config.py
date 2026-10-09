import os
import types
from functools import lru_cache
from typing import Any, Literal, Union, get_args, get_origin

from pydantic import ValidationInfo, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

EnvironmentType = Literal["local", "dev", "prod"]


def get_env_file() -> str | None:
    """ENVIRONMENT picks the .env file; "local" (default) relies on the defaults below + real env vars."""
    env = os.getenv("ENVIRONMENT", "local")
    env_files = {"local": ".env.local", "dev": ".env.dev", "prod": ".env.prod"}
    env_file = env_files.get(env)
    return env_file if env_file and os.path.exists(env_file) else None


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=get_env_file(), env_file_encoding="utf-8", extra="ignore")

    # App
    environment: EnvironmentType = "local"
    app_name: str = "{{PROJECT_NAME}}"
    app_version: str = "0.1.0"
    debug: bool = False
    api_prefix: str = ""
    cors_origins: list[str] = ["*"]
    log_level: str = "INFO"

    # Database
    database_driver: str = "{{DATABASE_DRIVER}}"
    database_host: str = "localhost"
    database_port: int = {{DATABASE_PORT}}
    database_user: str = "{{DATABASE_USER}}"
    database_password: str = "{{DATABASE_PASSWORD}}"
    database_name: str = "{{DATABASE_NAME}}"
    database_echo: bool = False
    database_pool_size: int = 5
    database_max_overflow: int = 10

    @property
    def database_url(self) -> str:
        if self.database_driver.startswith("sqlite"):
            return f"{self.database_driver}:///{self.database_name}"
        return (
            f"{self.database_driver}://{self.database_user}:{self.database_password}"
            f"@{self.database_host}:{self.database_port}/{self.database_name}"
        )

    @property
    def is_prod(self) -> bool:
        return self.environment == "prod"

    @field_validator("*", mode="before")
    @classmethod
    def _empty_to_none(cls, value: Any, info: ValidationInfo) -> Any:
        """`KEY=` in a .env file means "not set" for optional settings (pydantic would otherwise keep "")."""
        if value == "" and info.field_name:
            annotation = cls.model_fields[info.field_name].annotation
            if get_origin(annotation) in (Union, types.UnionType) and type(None) in get_args(annotation):
                return None
        return value

    # Integrations (added by add-core) go below this line


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
