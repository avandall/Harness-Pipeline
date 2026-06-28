from functools import lru_cache
from typing import Annotated, Any

from pydantic import AnyHttpUrl, BeforeValidator, Field, computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _parse_cors_origins(value: Any) -> list[str]:
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return []
        if stripped.startswith("["):
            return [item.strip().strip('"').strip("'") for item in stripped.strip("[]").split(",") if item.strip()]
        return [origin.strip() for origin in stripped.split(",") if origin.strip()]
    if isinstance(value, list):
        return value
    raise ValueError("BACKEND_CORS_ORIGINS must be a comma-separated string or JSON-style list.")


CorsOrigins = Annotated[list[AnyHttpUrl | str], BeforeValidator(_parse_cors_origins)]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    PROJECT_NAME: str = "Sanjeevani Backend Core"
    ENVIRONMENT: str = "local"
    API_V1_PREFIX: str = "/api/v1"

    SECRET_KEY: str = Field(min_length=32)
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    BACKEND_CORS_ORIGINS: CorsOrigins = ["http://localhost:3000", "http://localhost:5173", "http://localhost:8000"]

    POSTGRES_SERVER: str = "db"
    POSTGRES_PORT: int = 5432
    POSTGRES_USER: str = "sanjeevani"
    POSTGRES_PASSWORD: str = "sanjeevani_password"
    POSTGRES_DB: str = "sanjeevani_core"

    @computed_field
    @property
    def DATABASE_URL(self) -> str:
        return (
            f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_SERVER}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

