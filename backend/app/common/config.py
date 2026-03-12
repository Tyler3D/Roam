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


def getFrontendUrl() -> str:
    return getOptionalEnv("FRONTEND_URL") or "https://roam-alpha.web.app"


def getTwilioAccountSid() -> str | None:
    return getOptionalEnv("TWILIO_ACCOUNT_SID")


def getTwilioAuthToken() -> str | None:
    return getOptionalEnv("TWILIO_AUTH_TOKEN")


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

