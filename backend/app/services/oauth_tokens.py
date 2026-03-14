"""OAuth token storage with encryption at rest and refresh logic."""

import logging
from datetime import datetime
from uuid import UUID

from cryptography.fernet import Fernet, InvalidToken
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from sqlmodel import Session, select

from app.common.config import getOAuthEncryptionKey, getGoogleClientId, getGoogleClientSecret
from app.models.oauth_tokens import UserOAuthTokenModel

logger = logging.getLogger("roam.oauth_tokens")


def _get_fernet() -> Fernet | None:
    key = getOAuthEncryptionKey()
    if not key:
        return None
    try:
        # Key must be 44 chars base64url
        if isinstance(key, str):
            key = key.encode("ascii")
        return Fernet(key)
    except Exception:
        logger.warning("Invalid OAUTH_ENCRYPTION_KEY; OAuth token storage disabled")
        return None


def encrypt_token(plaintext: str) -> str | None:
    """Encrypt a token. Returns None if encryption is not configured."""
    f = _get_fernet()
    if not f:
        return None
    try:
        return f.encrypt(plaintext.encode("utf-8")).decode("ascii")
    except Exception:
        logger.exception("Token encryption failed")
        return None


def decrypt_token(encrypted: str) -> str | None:
    """Decrypt a token. Returns None on failure."""
    f = _get_fernet()
    if not f:
        return None
    try:
        return f.decrypt(encrypted.encode("ascii")).decode("utf-8")
    except InvalidToken:
        logger.warning("Token decryption failed: invalid token")
        return None
    except Exception:
        logger.exception("Token decryption failed")
        return None


def get_token_for_user(
    session: Session,
    user_id: UUID,
    provider: str = "google",
) -> tuple[str | None, str | None]:
    """
    Fetch and decrypt tokens for a user. Returns (access_token, refresh_token) or (None, None).
    """
    row = session.exec(
        select(UserOAuthTokenModel).where(
            UserOAuthTokenModel.userId == user_id,
            UserOAuthTokenModel.provider == provider,
        )
    ).first()
    if not row:
        return None, None

    access = decrypt_token(row.encryptedAccessToken)
    refresh = (
        decrypt_token(row.encryptedRefreshToken)
        if row.encryptedRefreshToken
        else None
    )
    return access, refresh


def upsert_token(
    session: Session,
    user_id: UUID,
    provider: str,
    access_token: str,
    refresh_token: str | None = None,
    expires_at: datetime | None = None,
) -> bool:
    """
    Encrypt and store tokens. Returns True on success, False if encryption is disabled.
    """
    enc_access = encrypt_token(access_token)
    if not enc_access:
        return False

    enc_refresh = encrypt_token(refresh_token) if refresh_token else None

    row = session.exec(
        select(UserOAuthTokenModel).where(
            UserOAuthTokenModel.userId == user_id,
            UserOAuthTokenModel.provider == provider,
        )
    ).first()

    if row:
        row.encryptedAccessToken = enc_access
        row.encryptedRefreshToken = enc_refresh
        row.expiresAt = expires_at
        row.updatedAt = datetime.utcnow()
        session.add(row)
    else:
        row = UserOAuthTokenModel(
            userId=user_id,
            provider=provider,
            encryptedAccessToken=enc_access,
            encryptedRefreshToken=enc_refresh,
            expiresAt=expires_at,
        )
        session.add(row)

    return True


def refresh_google_token(
    session: Session,
    user_id: UUID,
) -> str | None:
    """
    Refresh Google OAuth access token using stored refresh_token.
    Upserts new tokens and returns the new access_token, or None on failure.
    """
    access, refresh = get_token_for_user(session, user_id, "google")
    if not refresh:
        return None

    client_id = getGoogleClientId()
    client_secret = getGoogleClientSecret()
    if not client_id or not client_secret:
        logger.warning("GOOGLE_CLIENT_ID/SECRET not configured; cannot refresh token")
        return None

    creds = Credentials(
        token=None,
        refresh_token=refresh,
        token_uri="https://oauth2.googleapis.com/token",
        client_id=client_id,
        client_secret=client_secret,
    )
    try:
        creds.refresh(Request())
    except Exception as e:
        logger.warning("Google token refresh failed: %s", e)
        return None

    new_access = creds.token
    new_refresh = creds.refresh_token or refresh
    new_expires = creds.expiry

    if new_access and upsert_token(
        session, user_id, "google", new_access, new_refresh, new_expires
    ):
        return new_access
    return None
