import logging
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlmodel import Session, select, col

from app.auth.auth import getCurrentUser
from app.common.backendErrors import Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.notifications import NotificationModel, NotificationRead
from app.models.users import UserModel

logger = logging.getLogger("roam.notifications")
notificationsRouter = APIRouter()


@notificationsRouter.get("/notifications", response_model=list[NotificationRead])
def listNotifications(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[NotificationRead]:
    notifications = session.exec(
        select(NotificationModel)
        .where(NotificationModel.userId == user.id)
        .order_by(col(NotificationModel.createdAt).desc())
        .limit(50)
    ).all()
    return [NotificationRead.model_validate(n) for n in notifications]


@notificationsRouter.post("/notifications/{notificationId}/read", response_model=NotificationRead)
def markRead(
    notificationId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> NotificationRead:
    notification = session.get(NotificationModel, notificationId)
    if not notification:
        raise NotFound("Notification not found")
    if notification.userId != user.id:
        raise Forbidden("Not your notification")

    notification.isRead = True
    session.add(notification)
    commitAndRefresh(session, notification)
    return NotificationRead.model_validate(notification)


@notificationsRouter.post("/notifications/read-all", status_code=204)
def markAllRead(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    unread = session.exec(
        select(NotificationModel).where(
            NotificationModel.userId == user.id,
            NotificationModel.isRead == False,  # noqa: E712
        )
    ).all()
    for n in unread:
        n.isRead = True
        session.add(n)
    session.commit()
