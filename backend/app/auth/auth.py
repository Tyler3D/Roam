import logging
from typing import Any, Dict

from fastapi import Depends, Header, Request
from firebase_admin import auth
from sqlmodel import Session, select

from app.auth.firebase import getFirebaseApp
from app.common.backendErrors import NotFound, Unauthorized
from app.common.db import getSession
from app.models.users import UserModel


class CurrentAuth:
    """
    Auth context for the request: the DB user and decoded Firebase token.
    Use as a dependency via getCurrentAuth(). Later you can add methods
    scoped to this auth, e.g. getPermittedActivityPins(session).
    """
    def __init__(self, *, user: UserModel, decodedToken: Dict[str, Any]):
        self.user = user
        self.decodedToken = decodedToken


class OptionalAuth:
    """Like CurrentAuth but user may be None (e.g. first-time signup before DB user exists)."""
    def __init__(self, *, user: UserModel | None, decodedToken: Dict[str, Any]):
        self.user = user
        self.decodedToken = decodedToken


def getDecodedTokenFromRequest(request: Request) -> Dict[str, Any]:
    """Decoded Firebase token from request.state (set by middleware). Raises Unauthorized if missing uid."""
    decoded = getattr(request.state, "decodedToken", None)
    if not decoded:
        raise Unauthorized("Missing auth")
    uid = decoded.get("uid")
    if not uid:
        raise Unauthorized("Missing Firebase uid")
    return decoded


logger = logging.getLogger("roam.auth")


def getCurrentAuth(
    request: Request,
    session: Session = Depends(getSession),
) -> CurrentAuth:
    """FastAPI dependency: current user and decoded token for this request. Raises NotFound if no DB user."""
    decoded = getDecodedTokenFromRequest(request)
    uid = decoded.get("uid")
    user = session.exec(select(UserModel).where(UserModel.firebaseUid == uid)).first()
    if not user:
        logger.info(
            "user_not_found",
            extra={
                "firebaseUid": uid,
                "path": request.url.path,
                "email": decoded.get("email"),
            },
        )
        raise NotFound("User not found")
    return CurrentAuth(user=user, decodedToken=decoded)


def getCurrentUser(auth: CurrentAuth = Depends(getCurrentAuth)) -> UserModel:
    """FastAPI dependency: current DB user only. Use when you don't need the token."""
    return auth.user


def getOptionalAuth(
    request: Request,
    session: Session = Depends(getSession),
) -> OptionalAuth:
    """FastAPI dependency: decoded token and user if it exists. Use for endpoints that create the user (e.g. signup)."""
    decoded = getDecodedTokenFromRequest(request)
    uid = decoded.get("uid")
    user = session.exec(select(UserModel).where(UserModel.firebaseUid == uid)).first()
    return OptionalAuth(user=user, decodedToken=decoded)


def getBearerToken(authorization: str | None) -> str:
    if not authorization:
        raise Unauthorized("Missing Authorization header")
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise Unauthorized("Invalid Authorization header")
    return parts[1]


def getFirebaseBearerToken(
    *,
    authorization: str | None,
    xRoamAuthorization: str | None = None,
) -> str:
    """
    Prefer X-Roam-Authorization for the Firebase ID token.

    Google API Gateway often replaces Authorization with a Google ID token whose
    audience is the Cloud Run URL (invoker identity). That token is not a Firebase
    user JWT and fails verify_id_token. Clients should duplicate the Firebase token
    in X-Roam-Authorization; local dev can keep using Authorization only.
    """
    x = (xRoamAuthorization or "").strip()
    if x:
        return getBearerToken(x)
    return getBearerToken(authorization)


def verifyFirebaseTokenString(token: str) -> Dict[str, Any]:
    getFirebaseApp()
    try:
        decoded = auth.verify_id_token(token, check_revoked=True)
    except Exception as exc:  # firebase_admin raises several types
        # Response stays generic; logs carry the real reason (wrong project, bad key, etc.).
        logger.warning(
            "firebase_token_verify_failed",
            extra={"error": str(exc), "excType": type(exc).__name__},
            exc_info=exc,
        )
        raise Unauthorized("Invalid Firebase token") from exc
    return decoded


def verifyFirebaseToken(
    authorization: str | None = Header(default=None),
    x_roam_authorization: str | None = Header(default=None, alias="X-Roam-Authorization"),
) -> Dict[str, Any]:
    token = getFirebaseBearerToken(
        authorization=authorization,
        xRoamAuthorization=x_roam_authorization,
    )
    return verifyFirebaseTokenString(token)

