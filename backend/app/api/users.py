from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.auth.firebase import ensureFirebaseUser
from app.common.db import getSession
from app.models.users import UserCreate, UserModel, UserRead


usersRouter = APIRouter()


def _getDecodedToken(request: Request) -> dict:
    decodedToken = request.state.decodedToken
    firebaseUid = decodedToken.get("uid")
    if not firebaseUid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Firebase uid",
        )
    return decodedToken


def _getUserByFirebaseUid(session: Session, firebaseUid: str) -> UserModel | None:
    return session.exec(select(UserModel).where(UserModel.firebaseUid == firebaseUid)).first()


def _ensureFirebaseUserOrRaise(
    firebaseUid: str,
    email: str,
    displayName: str | None,
    photoUrl: str | None,
) -> None:
    try:
        ensureFirebaseUser(firebaseUid, email, displayName, photoUrl)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to create Firebase user",
        ) from exc


def _applyUserUpdates(existingUser: UserModel, request: UserCreate, email: str) -> None:
    existingUser.username = request.username
    existingUser.email = email
    existingUser.displayName = request.displayName
    existingUser.photoUrl = request.photoUrl


def _setActivationFromToken(user: UserModel, tokenEmailVerified: bool) -> None:
    user.emailVerified = tokenEmailVerified
    user.isActive = tokenEmailVerified


def _commitAndRefresh(session: Session, user: UserModel) -> None:
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already exists",
        ) from exc
    session.refresh(user)


@usersRouter.get("/me")
def getMe(
    request: Request,
    session: Session = Depends(getSession),
) -> UserRead:
    decodedToken = _getDecodedToken(request)
    firebaseUid = decodedToken.get("uid")
    existingUser = _getUserByFirebaseUid(session, firebaseUid)
    if not existingUser:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return UserRead.model_validate(existingUser)


@usersRouter.post("/users/verify", response_model=UserRead)
def verifyUserEmail(
    request: Request,
    session: Session = Depends(getSession),
) -> UserRead:
    decodedToken = _getDecodedToken(request)
    firebaseUid = decodedToken.get("uid")
    existingUser = _getUserByFirebaseUid(session, firebaseUid)
    if not existingUser:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    emailVerified = bool(decodedToken.get("email_verified"))
    if not emailVerified:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email not verified",
        )

    _setActivationFromToken(existingUser, True)
    session.add(existingUser)
    _commitAndRefresh(session, existingUser)
    return UserRead.model_validate(existingUser)


@usersRouter.post("/users", response_model=UserRead)
def createUser(
    request: UserCreate,
    httpRequest: Request,
    session: Session = Depends(getSession),
) -> UserRead:
    decodedToken = _getDecodedToken(httpRequest)
    firebaseUid = decodedToken.get("uid")
    tokenEmail = decodedToken.get("email")
    tokenEmailVerified = bool(decodedToken.get("email_verified"))
    email = tokenEmail or request.email
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email is required",
        )
    if not request.username.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username is required",
        )

    existingUser = _getUserByFirebaseUid(session, firebaseUid)

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
        _commitAndRefresh(session, existingUser)
        return UserRead.model_validate(existingUser)

    newUser = UserModel(
        firebaseUid=firebaseUid,
        username=request.username,
        email=email,
        displayName=request.displayName,
        photoUrl=request.photoUrl,
        isActive=False,
        emailVerified=tokenEmailVerified,
    )
    session.add(newUser)
    _commitAndRefresh(session, newUser)
    _ensureFirebaseUserOrRaise(
        firebaseUid,
        email,
        request.displayName,
        request.photoUrl,
    )
    _setActivationFromToken(newUser, tokenEmailVerified)
    session.add(newUser)
    _commitAndRefresh(session, newUser)
    return UserRead.model_validate(newUser)

