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
    reel_processed = "reel_processed"
    reel_needs_review = "reel_needs_review"
    coincidence_match = "coincidence_match"
    same_reel_saved = "same_reel_saved"
    trending_place = "trending_place"
    friend_request_accepted = "friend_request_accepted"
    proximity_save = "proximity_save"
    collection_idea_added = "collection_idea_added"
    weekly_digest = "weekly_digest"
    monthly_stats = "monthly_stats"


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
    placeId: Optional[UUID] = Field(default=None, foreign_key="places.id")
    ideaId: Optional[UUID] = Field(default=None, foreign_key="ideas.id")
    savedReelId: Optional[UUID] = Field(default=None, foreign_key="saved_reels.id")
    actorUserId: Optional[UUID] = Field(default=None, foreign_key="users.id")
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
    placeId: Optional[UUID] = None
    ideaId: Optional[UUID] = None
    savedReelId: Optional[UUID] = None
    actorUserId: Optional[UUID] = None
    title: str
    body: Optional[str] = None
    isRead: bool
    createdAt: datetime
