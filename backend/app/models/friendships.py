from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import CheckConstraint, Enum as SAEnum


class FriendshipStatus(str, Enum):
    pending = "pending"
    accepted = "accepted"


class FriendshipModel(SQLModel, table=True):
    __tablename__ = "friendships"
    __table_args__ = (
        CheckConstraint('"requesterId" <> "addresseeId"', name="friendships_no_self"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    requesterId: UUID = Field(foreign_key="users.id", nullable=False)
    addresseeId: UUID = Field(foreign_key="users.id", nullable=False)
    status: FriendshipStatus = Field(
        sa_column=Column(
            SAEnum(FriendshipStatus, name="friendshipStatus", create_type=False),
            nullable=False,
            default="pending",
        )
    )
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class FriendshipRead(SQLModel):
    id: UUID
    requesterId: UUID
    addresseeId: UUID
    status: FriendshipStatus
    createdAt: datetime
    friendId: Optional[UUID] = None
    friendFirstName: Optional[str] = None
    friendLastName: Optional[str] = None
    friendPhotoUrl: Optional[str] = None
