from typing import Any, Dict

from fastapi import Header, HTTPException, status
from firebase_admin import auth

from app.auth.firebase import getFirebaseApp


def getBearerToken(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Authorization header")
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Authorization header")
    return parts[1]


def verifyFirebaseTokenString(token: str) -> Dict[str, Any]:
    getFirebaseApp()
    try:
        decoded = auth.verify_id_token(token, check_revoked=True)
    except Exception as exc:  # firebase_admin raises several types
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Firebase token") from exc
    return decoded


def verifyFirebaseToken(authorization: str | None = Header(default=None)) -> Dict[str, Any]:
    token = getBearerToken(authorization)
    return verifyFirebaseTokenString(token)

