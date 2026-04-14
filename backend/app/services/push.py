"""Push notification dispatch via Firebase Cloud Messaging.

FCM HTTP calls run in a background thread pool so API responses are never
blocked by Google's push infrastructure.
"""

import logging
from concurrent.futures import ThreadPoolExecutor
from uuid import UUID

from firebase_admin import messaging
from sqlmodel import Session, select

from app.auth.firebase import getFirebaseApp
from app.common.db import getSession
from app.models.deviceTokens import DeviceTokenModel
from app.models.notifications import NotificationModel, NotificationType

logger = logging.getLogger("roam.push")

_executor = ThreadPoolExecutor(max_workers=4)


def _sendFcm(token: str, title: str, body: str | None, data: dict[str, str] | None) -> bool:
    """Send a single FCM push. Returns True on success, False when the token is invalid."""
    getFirebaseApp()
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data=data or {},
        token=token,
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(sound="default", badge=1),
            ),
        ),
    )
    try:
        messaging.send(message)
        return True
    except messaging.UnregisteredError:
        logger.info("fcm_token_unregistered", extra={"token": token[:20]})
        return False
    except messaging.SenderIdMismatchError:
        logger.warning("fcm_sender_id_mismatch", extra={"token": token[:20]})
        return True
    except Exception:
        logger.exception("fcm_send_failed", extra={"token": token[:20]})
        return True


def _deepLinkData(notification: NotificationModel) -> dict[str, str]:
    """Build deep-link payload for the client to route on notification tap."""
    data: dict[str, str] = {"type": notification.type.value}
    if notification.placeId:
        data["placeId"] = str(notification.placeId)
    if notification.ideaId:
        data["ideaId"] = str(notification.ideaId)
    if notification.collectionId:
        data["collectionId"] = str(notification.collectionId)
    if notification.savedReelId:
        data["savedReelId"] = str(notification.savedReelId)
    if notification.planId:
        data["planId"] = str(notification.planId)
    if notification.actorUserId:
        data["actorUserId"] = str(notification.actorUserId)
    return data


def _dispatchFcmBackground(
    userId: UUID, title: str, body: str | None, data: dict[str, str]
) -> None:
    """Runs in a background thread with its own DB session."""
    sessionGen = getSession()
    session = next(sessionGen)
    try:
        tokens = session.exec(
            select(DeviceTokenModel).where(DeviceTokenModel.userId == userId)
        ).all()
        if not tokens:
            return

        staleIds: list[UUID] = []
        for dt in tokens:
            ok = _sendFcm(dt.fcmToken, title, body, data)
            if not ok:
                staleIds.append(dt.id)

        for sid in staleIds:
            row = session.get(DeviceTokenModel, sid)
            if row:
                session.delete(row)
        if staleIds:
            session.commit()
    except Exception:
        logger.exception("background_fcm_dispatch_failed")
    finally:
        try:
            next(sessionGen, None)
        except StopIteration:
            pass


def sendPushToUser(
    session: Session,
    *,
    userId: UUID,
    notificationType: NotificationType,
    title: str,
    body: str | None = None,
    planId: UUID | None = None,
    collectionId: UUID | None = None,
    placeId: UUID | None = None,
    ideaId: UUID | None = None,
    savedReelId: UUID | None = None,
    actorUserId: UUID | None = None,
) -> NotificationModel:
    """Create a notification row synchronously, dispatch FCM in a background thread."""
    notification = NotificationModel(
        userId=userId,
        type=notificationType,
        title=title,
        body=body,
        planId=planId,
        collectionId=collectionId,
        placeId=placeId,
        ideaId=ideaId,
        savedReelId=savedReelId,
        actorUserId=actorUserId,
    )
    session.add(notification)
    session.flush()

    data = _deepLinkData(notification)
    _executor.submit(_dispatchFcmBackground, userId, title, body, data)
    return notification


def sendPushToUsers(
    session: Session,
    *,
    userIds: list[UUID],
    notificationType: NotificationType,
    title: str,
    body: str | None = None,
    planId: UUID | None = None,
    collectionId: UUID | None = None,
    placeId: UUID | None = None,
    ideaId: UUID | None = None,
    savedReelId: UUID | None = None,
    actorUserId: UUID | None = None,
) -> list[NotificationModel]:
    """Create notifications and dispatch push for multiple users."""
    notifications = []
    for uid in userIds:
        n = sendPushToUser(
            session,
            userId=uid,
            notificationType=notificationType,
            title=title,
            body=body,
            planId=planId,
            collectionId=collectionId,
            placeId=placeId,
            ideaId=ideaId,
            savedReelId=savedReelId,
            actorUserId=actorUserId,
        )
        notifications.append(n)
    return notifications
