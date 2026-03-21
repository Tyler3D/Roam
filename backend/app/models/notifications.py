from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import Enum as SAEnum


class NotificationType(str, Enum):
    invite_received = "invite_received"
    rsvp_accepted = "rsvp_accepted"
    rsvp_declined = "rsvp_declined"
    task_assigned = "task_assigned"
    plan_reminder = "plan_reminder"
    rate_prompt = "rate_prompt"
    friend_request = "friend_request"
    added_to_collection = "added_to_collection"


class NotificationModel(SQLModel, table=True):
    __tablename__ = "notifications"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    type: NotificationType = Field(
        sa_column=Column(
            SAEnum(NotificationType, name="notificationType", create_type=False),
            nullable=False,
        )
    )
    planId: Optional[UUID] = Field(default=None, foreign_key="plans.id")
    collectionId: Optional[UUID] = Field(default=None, foreign_key="collections.id")
    title: str = Field(nullable=False)
    body: Optional[str] = None
    isRead: bool = Field(default=False)
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class NotificationRead(SQLModel):
    id: UUID
    userId: UUID
    type: NotificationType
    planId: Optional[UUID] = None
    collectionId: Optional[UUID] = None
    title: str
    body: Optional[str] = None
    isRead: bool
    createdAt: datetime
