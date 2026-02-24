import os
from dotenv import load_dotenv


load_dotenv()


def getEnv(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def getOptionalEnv(name: str) -> str | None:
    return os.getenv(name)


def getFirebaseProjectId() -> str | None:
    return getOptionalEnv("FIREBASE_PROJECT_ID")


def getFirebasePrivateKeyId() -> str | None:
    return getOptionalEnv("FIREBASE_PRIVATE_KEY_ID")


def getFirebasePrivateKey() -> str | None:
    return getOptionalEnv("FIREBASE_PRIVATE_KEY")


def getFirebaseClientEmail() -> str | None:
    return getOptionalEnv("FIREBASE_CLIENT_EMAIL")


def IS_DEV() -> bool:
    environment = getOptionalEnv("ENVIRONMENT")
    if environment not in {"dev", "prod"}:
        raise RuntimeError("ENVIRONMENT must be 'dev' or 'prod'.")
    return environment == "dev"


def getCorsOrigins() -> list[str]:
    """Comma-separated origins for CORS (prod). In dev we use localhost."""
    raw = getOptionalEnv("CORS_ORIGINS") or getOptionalEnv("FRONTEND_ORIGIN")
    if not raw:
        return []
    return [o.strip() for o in raw.split(",") if o.strip()]


def getTrustedAuthProviders() -> set[str]:
    rawProviders = getOptionalEnv("TRUSTED_AUTH_PROVIDERS") or "google.com,password"
    providers = {value.strip() for value in rawProviders.split(",") if value.strip()}
    return providers


def getDatabaseUrl() -> str:
    return getEnv("DATABASE_URL")


def getOpenAIApiKey() -> str:
    return getEnv("OPENAI_API_KEY")


def getGoogleMapsApiKey() -> str | None:
    return getOptionalEnv("GOOGLE_MAPS_API_KEY")

