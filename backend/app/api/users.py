from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, select, col, or_

from app.auth.auth import CurrentAuth, OptionalAuth, getCurrentAuth, getCurrentUser, getOptionalAuth
from app.auth.firebase import ensureFirebaseUser
from app.common.backendErrors import BadRequest, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.users import UserCreate, UserModel, UserRead, UserUpdate

usersRouter = APIRouter()

USER_CONSTRAINT_MESSAGES = {
    "users_username_key": "Username already exists",
    "users_email_key": "Email already exists",
    "users_firebaseUid_key": "User already exists",
}


def _ensureFirebaseUserOrRaise(
    firebaseUid: str,
    email: str,
    firstName: str | None,
    photoUrl: str | None,
) -> None:
    try:
        displayName = firstName or ""
        ensureFirebaseUser(firebaseUid, email, displayName, photoUrl)
    except Exception as exc:
        raise BadRequest("Failed to create Firebase user") from exc


def _applyUserUpdates(existingUser: UserModel, request: UserCreate, email: str) -> None:
    if request.username:
        existingUser.username = request.username
    existingUser.email = email
    existingUser.firstName = request.firstName
    existingUser.lastName = request.lastName
    existingUser.photoUrl = request.photoUrl


def _setActivationFromToken(user: UserModel, tokenEmailVerified: bool) -> None:
    user.emailVerified = tokenEmailVerified
    user.isActive = tokenEmailVerified


@usersRouter.get("/me")
def getMe(user: UserModel = Depends(getCurrentUser)) -> UserRead:
    return UserRead.model_validate(user)


@usersRouter.put("/me", response_model=UserRead)
def updateMe(
    body: UserUpdate,
    auth: CurrentAuth = Depends(getCurrentAuth),
    session: Session = Depends(getSession),
) -> UserRead:
    user = auth.user
    update_data = body.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(user, key, value)
    session.add(user)
    commitAndRefresh(session, user, constraintMessages=USER_CONSTRAINT_MESSAGES)
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

    existingUser = auth.user

    if existingUser:
        if not existingUser.isActive:
            _ensureFirebaseUserOrRaise(
                firebaseUid,
                email,
                request.firstName,
                request.photoUrl,
            )
            _setActivationFromToken(existingUser, tokenEmailVerified)
        _applyUserUpdates(existingUser, request, email)
        session.add(existingUser)
        commitAndRefresh(session, existingUser, constraintMessages=USER_CONSTRAINT_MESSAGES)
        return UserRead.model_validate(existingUser)

    _ensureFirebaseUserOrRaise(
        firebaseUid,
        email,
        request.firstName,
        request.photoUrl,
    )
    newUser = UserModel(
        firebaseUid=firebaseUid,
        username=request.username,
        email=email,
        firstName=request.firstName,
        lastName=request.lastName,
        phone=request.phone,
        photoUrl=request.photoUrl,
        isActive=tokenEmailVerified,
        emailVerified=tokenEmailVerified,
    )
    session.add(newUser)
    commitAndRefresh(session, newUser, constraintMessages=USER_CONSTRAINT_MESSAGES)
    return UserRead.model_validate(newUser)


@usersRouter.get("/users/search", response_model=list[UserRead])
def searchUsers(
    q: str = Query(..., min_length=1),
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[UserRead]:
    q_lower = q.lower()
    results = session.exec(
        select(UserModel).where(
            UserModel.id != user.id,
            or_(
                col(UserModel.firstName).ilike(f"%{q_lower}%"),
                col(UserModel.lastName).ilike(f"%{q_lower}%"),
                col(UserModel.username).ilike(f"%{q_lower}%"),
            ),
        ).limit(20)
    ).all()
    return [UserRead.model_validate(u) for u in results]
