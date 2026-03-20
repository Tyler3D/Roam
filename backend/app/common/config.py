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


def getCorsAllowOrigins() -> list[str]:
    """Origins allowed for CORS and manual Access-Control-Allow-* on error responses."""
    if IS_DEV():
        return [
            "http://localhost:3000",
            "http://127.0.0.1:3000",
            "http://localhost:5173",
            "http://127.0.0.1:5173",
        ]
    return ["https://roam-alpha.web.app", "https://roam-alpha.firebaseapp.com"]

def getTrustedAuthProviders() -> set[str]:
    rawProviders = getOptionalEnv("TRUSTED_AUTH_PROVIDERS") or "google.com,password"
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

def getTwilioFromNumber() -> str | None:
    return getOptionalEnv("TWILIO_FROM_NUMBER")


def getSmtpHost() -> str | None:
    return getOptionalEnv("SMTP_HOST")


def getSmtpPort() -> int:
    return int(getOptionalEnv("SMTP_PORT") or "587")


def getSmtpUser() -> str | None:
    return getOptionalEnv("SMTP_USER")


def getSmtpPassword() -> str | None:
    return getOptionalEnv("SMTP_PASSWORD")


def getSmtpFromEmail() -> str:
    return getOptionalEnv("SMTP_FROM_EMAIL") or "noreply@roam.app"


def getSendGridApiKey() -> str | None:
    return getOptionalEnv("SENDGRID_API_KEY")


def getOAuthEncryptionKey() -> str:
    """Base64-encoded 32-byte key for Fernet. Required for OAuth token storage."""
    key = getOptionalEnv("OAUTH_ENCRYPTION_KEY")
    if not key:
        raise RuntimeError(
            "OAUTH_ENCRYPTION_KEY is not set. "
            "Generate with: python -c \"from cryptography.fernet import Fernet; "
            "print(Fernet.generate_key().decode())\""
        )
    return key
