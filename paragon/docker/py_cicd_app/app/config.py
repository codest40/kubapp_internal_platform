import os

from pydantic import BaseModel


class Settings(BaseModel):
    """Application configuration."""

    app_name: str = "Python Quality App"
    app_version: str = "1.0.0"
    environment: str = "development"

    @classmethod
    def from_environment(cls) -> "Settings":
        """Build settings from environment variables."""
        return cls(
            app_name=os.getenv("APP_NAME", "Python Quality App"),
            app_version=os.getenv("APP_VERSION", "1.0.0"),
            environment=os.getenv("APP_ENV", "development"),
        )


settings = Settings.from_environment()
