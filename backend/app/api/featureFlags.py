"""Feature flag endpoints — per-user flag CRUD."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.auth.auth import getCurrentUser
from app.common.db import getSession
from app.models.featureFlags import (
    FeatureFlagRead,
    FeatureFlagUpdate,
    UserFeatureFlagModel,
)
from app.models.users import UserModel

featureFlagsRouter = APIRouter()


@featureFlagsRouter.get("/feature-flags", response_model=list[FeatureFlagRead])
def listFeatureFlags(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[FeatureFlagRead]:
    """Return all flags for the authenticated user."""
    rows = session.exec(
        select(UserFeatureFlagModel).where(
            UserFeatureFlagModel.user_id == user.id,
        )
    ).all()
    return [
        FeatureFlagRead(flagName=r.flag_name, enabled=r.enabled)
        for r in rows
    ]


@featureFlagsRouter.put("/feature-flags/{flagName}", response_model=FeatureFlagRead)
def upsertFeatureFlag(
    flagName: str,
    body: FeatureFlagUpdate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> FeatureFlagRead:
    """Create or update a single feature flag for the authenticated user."""
    existing = session.exec(
        select(UserFeatureFlagModel).where(
            UserFeatureFlagModel.user_id == user.id,
            UserFeatureFlagModel.flag_name == flagName,
        )
    ).first()

    if existing:
        existing.enabled = body.enabled
        existing.updated_at = datetime.now(timezone.utc)
        session.add(existing)
    else:
        existing = UserFeatureFlagModel(
            user_id=user.id,
            flag_name=flagName,
            enabled=body.enabled,
        )
        session.add(existing)

    session.commit()
    session.refresh(existing)

    return FeatureFlagRead(flagName=existing.flag_name, enabled=existing.enabled)
