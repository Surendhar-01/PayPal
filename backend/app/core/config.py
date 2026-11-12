import os
from functools import lru_cache
from typing import Any, List, Union
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Determine base directory containing .env
_BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_ENV_FILE_PATH = os.path.join(_BACKEND_DIR, ".env")


class Settings(BaseSettings):
    """
    Application Settings configuration via Pydantic BaseSettings.
    Loads values from environment variables or backend/.env file.
    """
    model_config = SettingsConfigDict(
        env_file=(_ENV_FILE_PATH, ".env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )

    # Core Application
    PROJECT_NAME: str = "MarketTwin API"
    VERSION: str = "0.1.0"
    ENVIRONMENT: str = "development"
    DEBUG: bool = True
    API_V1_STR: str = "/api/v1"

    @field_validator("DEBUG", mode="before")
    @classmethod
    def parse_debug(cls, v: Any) -> bool:
        if isinstance(v, str):
            return v.lower() in ("true", "1", "t", "yes", "y", "dev", "development")
        return bool(v)

    # CORS
    ALLOWED_ORIGINS: Union[str, List[str]] = (
        "http://localhost:5173,http://127.0.0.1:5173,http://10.107.161.106:5173"
    )

    # Supabase Configuration
    SUPABASE_URL: str = Field(default="", description="Supabase project URL")
    SUPABASE_KEY: str = Field(default="", description="Supabase anon public key")
    SUPABASE_SERVICE_ROLE_KEY: str = Field(default="", description="Supabase service role secret key")
    SUPABASE_JWT_SECRET: str = Field(default="", description="Supabase JWT secret for token verification")
    DEMAND_PERSISTENCE_ENABLED: bool = Field(
        default=False,
        description="Enable demand submission only after transactional schema verification.",
    )
    DEMAND_ANALYSIS_ENABLED: bool = Field(
        default=False,
        description="Enable cross-customer demand analysis only after privacy verification.",
    )
    FRONTEND_URL: str = Field(default="http://localhost:5173", description="Frontend base URL for auth redirects")
    GROQ_API_KEY: str = Field(default="", description="Groq API key for AI features")
    GROQ_MODEL: str = Field(
        default="llama-3.1-8b-instant",
        description="Groq chat completion model used for AI conversations",
    )
    AI_PROVIDER: str = Field(default="groq", description="AI provider used for requirement conversations")
    GROQ_HEALTH_TIMEOUT_SECONDS: float = Field(
        default=2.0,
        gt=0,
        le=10,
        description="Timeout for the Groq dependency probe used by the health endpoint",
    )
    BUYORA_CATALOGUE_API_URL: str = Field(
        default="https://buyora-backend-0kae.onrender.com/api/products",
        description="Buyora catalogue API endpoint used for product matching",
    )
    CATALOGUE_API_TIMEOUT_SECONDS: float = Field(
        default=30.0,
        gt=0,
        le=120,
        description="Timeout for Buyora catalogue requests",
    )
    CATALOGUE_API_TOTAL_TIMEOUT_SECONDS: float = Field(
        default=75.0,
        gt=0,
        le=180,
        description="Maximum time allowed to retrieve all Buyora catalogue pages",
    )
    CATALOGUE_API_MAX_RETRIES: int = Field(
        default=1,
        ge=0,
        le=3,
        description="Maximum retries for transient Buyora catalogue failures",
    )
    PAYPAL_CLIENT_ID: str = Field(default="", description="PayPal client ID")
    PAYPAL_CLIENT_SECRET: str = Field(default="", description="PayPal client secret")
    PAYPAL_MODE: str = Field(default="sandbox", description="PayPal mode: sandbox or live")
    PAYPAL_INR_TO_USD_TEST_RATE: str = Field(
        default="",
        description="Explicit INR-to-USD exchange rate for PayPal Sandbox testing; USD per INR.",
    )

    @property
    def cors_origins(self) -> List[str]:
        """Returns allowed origins parsed into a clean list of strings."""
        if isinstance(self.ALLOWED_ORIGINS, list):
            return self.ALLOWED_ORIGINS
        if isinstance(self.ALLOWED_ORIGINS, str):
            return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",") if origin.strip()]
        return ["*"]

    @property
    def is_supabase_configured(self) -> bool:
        """Checks if Supabase credentials are valid non-placeholder values."""
        return bool(
            self.SUPABASE_URL
            and self.SUPABASE_KEY
            and "placeholder" not in self.SUPABASE_URL
            and "placeholder" not in self.SUPABASE_KEY
        )


@lru_cache()
def get_settings() -> Settings:
    """Returns cached instance of Settings."""
    return Settings()
