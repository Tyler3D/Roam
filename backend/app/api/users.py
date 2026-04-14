import logging
from datetime import datetime

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlmodel import Session, select, col, or_
from sqlalchemy import delete as sa_delete, update as sa_update

from app.auth.auth import CurrentAuth, OptionalAuth, getCurrentAuth, getCurrentUser, getOptionalAuth
from app.auth.firebase import ensureFirebaseUser, getFirebaseApp
from firebase_admin import auth as firebaseAuth
from sqlalchemy.exc import IntegrityError

from app.common.backendErrors import BadRequest, Conflict, InternalServerError, NotFound
from app.common.db import commitAndRefresh, getSession, getUniqueConstraintName
from app.models.collections import CollectionIdeaModel, CollectionMemberModel, CollectionModel
from app.models.coincidenceNotificationsSent import CoincidenceNotificationSentModel
from app.models.deviceTokens import DeviceTokenModel
from app.models.featureFlags import UserFeatureFlagModel
from app.models.friendships import FriendshipModel
from app.models.ideas import IdeaModel
from app.models.ingestion import IngestionJobModel
from app.models.notifications import NotificationModel
from app.models.oauth_tokens import UserOAuthTokenModel
from app.models.pipeline import PipelineResultModel, PlaceSuggestionModel
from app.models.plans import PlanMemberModel, PlanModel
from app.models.savedReels import ReelCandidateUserPlaceModel, ReelIngestCandidateModel, SavedReelModel
from app.models.trendingNotificationsSent import TrendingNotificationSentModel
from app.models.users import UserCreate, UserModel, UserRead, UserUpdate
from app.services.collectionLinks import ensurePersonalDefaultCollection
from app.services.oauth_tokens import upsert_token

logger = logging.getLogger("roam.users")
usersRouter = APIRouter()


class OAuthTokenStore(BaseModel):
    """Payload for storing OAuth tokens (sent from client after Google sign-in)."""

    accessToken: str
    refreshToken: str | None = None
    expiresAt: datetime | None = None

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
        existingUser.username = request.username.strip().lower()
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
    if "username" in update_data and update_data["username"]:
        update_data["username"] = update_data["username"].strip().lower()
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
        try:
            session.flush()
        except IntegrityError as exc:
            session.rollback()
            constraintName = getUniqueConstraintName(exc)
            detail = USER_CONSTRAINT_MESSAGES.get(constraintName, "Resource already exists") if constraintName else "Resource already exists"
            raise Conflict(detail) from exc
        ensurePersonalDefaultCollection(session, existingUser.id)
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
        username=request.username.strip().lower() if request.username else None,
        email=email,
        firstName=request.firstName,
        lastName=request.lastName,
        phone=request.phone,
        photoUrl=request.photoUrl,
        isActive=tokenEmailVerified,
        emailVerified=tokenEmailVerified,
    )
    session.add(newUser)
    try:
        session.flush()
    except IntegrityError as exc:
        session.rollback()
        constraintName = getUniqueConstraintName(exc)
        detail = USER_CONSTRAINT_MESSAGES.get(constraintName, "Resource already exists") if constraintName else "Resource already exists"
        raise Conflict(detail) from exc
    ensurePersonalDefaultCollection(session, newUser.id)
    commitAndRefresh(session, newUser, constraintMessages=USER_CONSTRAINT_MESSAGES)
    logger.info(
        "user_created",
        extra={"firebaseUid": firebaseUid, "userId": str(newUser.id), "email": email},
    )
    return UserRead.model_validate(newUser)


@usersRouter.post("/users/oauth-token")
def storeOAuthToken(
    body: OAuthTokenStore,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> dict:
    """
    Store Google OAuth tokens (encrypted) for calendar integration.
    Call after Google sign-in when credential.accessToken is available.
    Send expiresAt (ISO datetime) when available from token response for cheap expiry checks.
    """
    ok = upsert_token(
        session,
        user.id,
        "google",
        body.accessToken,
        body.refreshToken,
        body.expiresAt,
    )
    if not ok:
        raise InternalServerError()
    session.commit()
    return {"ok": True}


@usersRouter.get("/users/check-username")
def checkUsername(
    username: str = Query(..., min_length=1),
    session: Session = Depends(getSession),
) -> dict:
    """Check if username is available. No auth required — used during onboarding."""
    exists = (
        session.exec(
            select(UserModel).where(col(UserModel.username).ilike(username.strip()))
        ).first()
        is not None
    )
    return {"available": not exists}


@usersRouter.delete("/me", status_code=204)
def deleteMe(
    auth: CurrentAuth = Depends(getCurrentAuth),
    session: Session = Depends(getSession),
) -> None:
    """
    Permanently delete the authenticated user and all their data.
    Firebase Auth account is deleted server-side after the DB commit.
    """
    user = auth.user
    uid = user.firebaseUid

    # Deletion order respects all FK constraints — children before parents throughout.

    # ── Reel pipeline ────────────────────────────────────────────────────────────
    # reel_candidate_user_places → reel_ingest_candidates → saved_reels → reel_ingestion_jobs

    session.exec(sa_delete(ReelCandidateUserPlaceModel).where(ReelCandidateUserPlaceModel.user_id == user.id))

    reel_ids_subq = select(SavedReelModel.id).where(SavedReelModel.userId == user.id)
    session.exec(sa_delete(ReelIngestCandidateModel).where(col(ReelIngestCandidateModel.savedReelId).in_(reel_ids_subq)))

    # ── Pipeline results ──────────────────────────────────────────────────────────
    # place_suggestions → pipeline_results (which references ideas AND reel_ingestion_jobs)
    # Must be deleted before ideas and ingestion_jobs.

    job_ids_subq = select(IngestionJobModel.id).where(IngestionJobModel.userId == user.id)
    idea_ids_subq = select(IdeaModel.id).where(IdeaModel.userId == user.id)
    pipeline_ids_subq = select(PipelineResultModel.id).where(
        or_(
            col(PipelineResultModel.jobId).in_(job_ids_subq),
            col(PipelineResultModel.ideaId).in_(idea_ids_subq),
        )
    )
    session.exec(sa_delete(PlaceSuggestionModel).where(col(PlaceSuggestionModel.resultId).in_(pipeline_ids_subq)))
    session.exec(sa_delete(PipelineResultModel).where(
        or_(
            col(PipelineResultModel.jobId).in_(job_ids_subq),
            col(PipelineResultModel.ideaId).in_(idea_ids_subq),
        )
    ))

    # ── Ideas ─────────────────────────────────────────────────────────────────────
    # ideas.savedReelId → saved_reels, so ideas must go before saved_reels.
    # Other users' plans may have ideaId pointing here — null those out first.

    session.exec(sa_update(PlanModel).where(col(PlanModel.ideaId).in_(idea_ids_subq)).values(ideaId=None))
    session.exec(sa_delete(CollectionIdeaModel).where(col(CollectionIdeaModel.ideaId).in_(idea_ids_subq)))
    session.exec(sa_delete(IdeaModel).where(IdeaModel.userId == user.id))

    # ── Saved reels + ingestion jobs ──────────────────────────────────────────────
    session.exec(sa_delete(SavedReelModel).where(SavedReelModel.userId == user.id))
    session.exec(sa_delete(IngestionJobModel).where(IngestionJobModel.userId == user.id))

    # ── Plans ─────────────────────────────────────────────────────────────────────
    session.exec(sa_delete(PlanMemberModel).where(PlanMemberModel.userId == user.id))
    plan_ids_subq = select(PlanModel.id).where(PlanModel.creatorId == user.id)
    session.exec(sa_delete(PlanMemberModel).where(col(PlanMemberModel.planId).in_(plan_ids_subq)))
    session.exec(sa_delete(PlanModel).where(PlanModel.creatorId == user.id))

    # ── Collections ───────────────────────────────────────────────────────────────
    coll_ids_subq = select(CollectionModel.id).where(CollectionModel.creatorId == user.id)
    session.exec(sa_delete(CollectionIdeaModel).where(col(CollectionIdeaModel.collectionId).in_(coll_ids_subq)))
    session.exec(sa_delete(CollectionMemberModel).where(col(CollectionMemberModel.collectionId).in_(coll_ids_subq)))
    session.exec(sa_delete(CollectionModel).where(CollectionModel.creatorId == user.id))
    session.exec(sa_delete(CollectionMemberModel).where(CollectionMemberModel.userId == user.id))

    # ── Social + notifications ────────────────────────────────────────────────────
    session.exec(sa_delete(FriendshipModel).where(
        or_(FriendshipModel.requesterId == user.id, FriendshipModel.addresseeId == user.id)
    ))
    session.exec(sa_delete(NotificationModel).where(
        or_(NotificationModel.userId == user.id, NotificationModel.actorUserId == user.id)
    ))
    session.exec(sa_delete(CoincidenceNotificationSentModel).where(CoincidenceNotificationSentModel.userId == user.id))
    session.exec(sa_delete(TrendingNotificationSentModel).where(TrendingNotificationSentModel.userId == user.id))

    # ── Device tokens, feature flags, oauth tokens ────────────────────────────────
    session.exec(sa_delete(DeviceTokenModel).where(DeviceTokenModel.userId == user.id))
    session.exec(sa_delete(UserFeatureFlagModel).where(UserFeatureFlagModel.user_id == user.id))
    session.exec(sa_delete(UserOAuthTokenModel).where(UserOAuthTokenModel.userId == user.id))

    # finally the user row itself
    session.delete(user)
    session.commit()

    logger.info("user_deleted", extra={"firebaseUid": uid, "userId": str(user.id)})

    # Delete from Firebase Auth after DB commit so the token remains valid during the request.
    if uid:
        try:
            getFirebaseApp()
            firebaseAuth.delete_user(uid)
        except Exception:
            logger.warning("deleteMe_firebase_failed", extra={"firebaseUid": uid})


@usersRouter.get("/users/search", response_model=list[UserRead])
def searchUsers(
    q: str = Query(..., min_length=2),
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
        ).limit(10)
    ).all()
    return [UserRead.model_validate(u) for u in results]
