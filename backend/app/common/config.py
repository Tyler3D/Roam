import os
from dotenv import load_dotenv


load_dotenv()


def getEnv(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def getFirebaseServiceAccountJson() -> str:
    """Full Firebase service-account JSON."""
    return getEnv("FIREBASE_SERVICE_ACCOUNT_JSON")


def IS_DEV() -> bool:
    environment = getEnv("ENVIRONMENT")
    if environment not in {"dev", "staging", "prod"}:
        raise RuntimeError("ENVIRONMENT must be 'dev', 'staging', or 'prod'.")
    return environment == "dev"


def getCorsAllowOrigins() -> list[str]:
    """Origins allowed for CORS and manual Access-Control-Allow-* on error responses."""
    if IS_DEV():
        return [
            "http://localhost:3000",
            "http://127.0.0.1:3000",
            "http://localhost:5173",
            "http://127.0.0.1:5173",
        ]
    # In prod/staging, honour CORS_ORIGINS env var if set; otherwise use defaults.
    custom = os.getenv("CORS_ORIGINS")
    if custom:
        return [o.strip() for o in custom.split(",") if o.strip()]
    return ["https://roam-alpha.web.app", "https://roam-alpha.firebaseapp.com"]

def getTrustedAuthProviders() -> set[str]:
    rawProviders = os.getenv("TRUSTED_AUTH_PROVIDERS") or "google.com,password,apple.com"
    providers = {value.strip() for value in rawProviders.split(",") if value.strip()}
    return providers


def getDatabaseUrl() -> str:
    return getEnv("DATABASE_URL")


def getGeminiApiKey() -> str:
    """API key for Google Gemini. Required for idea interpretation and reel processing."""
    return getEnv("GEMINI_API_KEY")


def getGoogleMapsApiKey() -> str:
    """API key for Google Maps Places API. Required for place suggestions."""
    return getEnv("GOOGLE_MAPS_API_KEY")

def getGoogleClientId() -> str:
    """Google OAuth client ID. Required for Google sign-in and Calendar API."""
    return getEnv("GOOGLE_CLIENT_ID")

def getGoogleClientSecret() -> str:
    """Google OAuth client secret. Required for token refresh with Google APIs."""
    return getEnv("GOOGLE_CLIENT_SECRET")

def getGcsServiceAccountJson() -> str:
    """JSON string for a GCS-enabled service account. Secret — never log."""
    return getEnv("GCS_SERVICE_ACCOUNT_JSON")


def getGcsReelBucketName() -> str:
    return getEnv("GCS_REEL_BUCKET_NAME")


def getOAuthEncryptionKey() -> str:
    """Base64-encoded 32-byte key for Fernet. Required for OAuth token storage."""
    return getEnv("OAUTH_ENCRYPTION_KEY")
