from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.auth.auth import CurrentAuth, OptionalAuth, getCurrentAuth, getCurrentUser, getOptionalAuth
from app.auth.firebase import ensureFirebaseUser
from app.common.backendErrors import BadRequest, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.users import UserCreate, UserModel, UserRead

usersRouter = APIRouter()

USER_CONSTRAINT_MESSAGES = {
    "users_username_key": "Username already exists",
    "users_email_key": "Email already exists",
    "users_firebaseUid_key": "User already exists",
}


def _ensureFirebaseUserOrRaise(
    firebaseUid: str,
    email: str,
    displayName: str | None,
    photoUrl: str | None,
) -> None:
    """Ensure Firebase has this user (get-or-create). Idempotent: safe to call on retries."""
    try:
        ensureFirebaseUser(firebaseUid, email, displayName, photoUrl)
    except Exception as exc:
        raise BadRequest("Failed to create Firebase user") from exc


def _applyUserUpdates(existingUser: UserModel, request: UserCreate, email: str) -> None:
    existingUser.username = request.username
    existingUser.email = email
    existingUser.displayName = request.displayName
    existingUser.photoUrl = request.photoUrl


def _setActivationFromToken(user: UserModel, tokenEmailVerified: bool) -> None:
    user.emailVerified = tokenEmailVerified
    user.isActive = tokenEmailVerified


@usersRouter.get("/me")
def getMe(user: UserModel = Depends(getCurrentUser)) -> UserRead:
    return UserRead.model_validate(user)


@usersRouter.post("/users/verify", response_model=UserRead)
def verifyUserEmail(
    auth: CurrentAuth = Depends(getCurrentAuth),
    session: Session = Depends(getSession),
) -> UserRead:
    if not bool(auth.decodedToken.get("email_verified")):
        raise BadRequest("Email not verified")
    _setActivationFromToken(auth.user, True)
    session.add(auth.user)
    commitAndRefresh(session, auth.user, constraintMessages=USER_CONSTRAINT_MESSAGES)
    return UserRead.model_validate(auth.user)


@usersRouter.post("/users", response_model=UserRead)
def createUser(
    request: UserCreate,
    auth: OptionalAuth = Depends(getOptionalAuth),
    session: Session = Depends(getSession),
) -> UserRead:
    decodedToken = auth.decodedToken
    firebaseUid = decodedToken.get("uid")
    tokenEmail = decodedToken.get("email")
    tokenEmailVerified = bool(decodedToken.get("email_verified"))
    email = tokenEmail or request.email
    if not email:
        raise BadRequest("Email is required")
    if not request.username.strip():
        raise BadRequest("Username is required")

    existingUser = auth.user

    if existingUser:
        if not existingUser.isActive:
            _ensureFirebaseUserOrRaise(
                firebaseUid,
                email,
                request.displayName,
                request.photoUrl,
            )
            _setActivationFromToken(existingUser, tokenEmailVerified)
        _applyUserUpdates(existingUser, request, email)
        session.add(existingUser)
        commitAndRefresh(session, existingUser, constraintMessages=USER_CONSTRAINT_MESSAGES)
        return UserRead.model_validate(existingUser)

    # New user: ensure Firebase first (idempotent), then single DB commit. Retries are safe.
    _ensureFirebaseUserOrRaise(
        firebaseUid,
        email,
        request.displayName,
        request.photoUrl,
    )
    newUser = UserModel(
        firebaseUid=firebaseUid,
        username=request.username,
        email=email,
        displayName=request.displayName,
        photoUrl=request.photoUrl,
        isActive=tokenEmailVerified,
        emailVerified=tokenEmailVerified,
    )
    session.add(newUser)
    commitAndRefresh(session, newUser, constraintMessages=USER_CONSTRAINT_MESSAGES)
    return UserRead.model_validate(newUser)

