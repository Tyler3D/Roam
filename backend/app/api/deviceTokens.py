import logging
from datetime import datetime

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.auth.auth import getCurrentUser
from app.common.db import getSession
from app.models.deviceTokens import DeviceTokenCreate, DeviceTokenModel, DeviceTokenRead
from app.models.users import UserModel

logger = logging.getLogger("roam.device_tokens")
deviceTokensRouter = APIRouter()


@deviceTokensRouter.post("/device-tokens", response_model=DeviceTokenRead, status_code=201)
def registerDeviceToken(
    body: DeviceTokenCreate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> DeviceTokenRead:
    """Register or update an FCM device token for push notifications."""
    existing = session.exec(
        select(DeviceTokenModel).where(DeviceTokenModel.fcmToken == body.fcmToken)
    ).first()

    if existing:
        if existing.userId != user.id:
            existing.userId = user.id
        existing.platform = body.platform
        existing.updatedAt = datetime.utcnow()
        session.add(existing)
        session.commit()
        session.refresh(existing)
        return DeviceTokenRead.model_validate(existing)

    token = DeviceTokenModel(
        userId=user.id,
        fcmToken=body.fcmToken,
        platform=body.platform,
    )
    session.add(token)
    session.commit()
    session.refresh(token)
    return DeviceTokenRead.model_validate(token)


@deviceTokensRouter.delete("/device-tokens", status_code=204)
def unregisterDeviceToken(
    body: DeviceTokenCreate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    """Remove an FCM device token (e.g. on sign-out)."""
    existing = session.exec(
        select(DeviceTokenModel).where(
            DeviceTokenModel.fcmToken == body.fcmToken,
            DeviceTokenModel.userId == user.id,
        )
    ).first()
    if existing:
        session.delete(existing)
        session.commit()
