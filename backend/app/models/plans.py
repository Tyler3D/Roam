from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import CheckConstraint, Enum as SAEnum

from app.models.plan_enums import MemberRole, PlanStatus, RsvpStatus


class PlanModel(SQLModel, table=True):
    __tablename__ = "plans"
    __table_args__ = (
        CheckConstraint(
            '"rating" IS NULL OR ("rating" >= 1 AND "rating" <= 5)',
            name="plans_rating_range",
        ),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    creatorId: UUID = Field(foreign_key="users.id", nullable=False)
    placeId: Optional[UUID] = Field(default=None, foreign_key="places.id")
    ideaId: Optional[UUID] = Field(default=None, foreign_key="ideas.id")
    title: str = Field(nullable=False)
    scheduledAt: Optional[datetime] = None
    status: PlanStatus = Field(
        sa_column=Column(
            SAEnum(PlanStatus, name="planStatus", create_type=False),
            nullable=False,
            default="draft",
        )
    )
    shareCode: str = Field(nullable=False, unique=True)
    rawPrompt: Optional[str] = None
    estimatedMinutes: int = Field(default=60)
    calendarEventId: Optional[str] = None
    partySize: int = Field(default=1)
    rating: Optional[int] = None
    taskNotes: str = Field(default="")
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


class PlanMemberModel(SQLModel, table=True):
    __tablename__ = "plan_members"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    planId: UUID = Field(foreign_key="plans.id", nullable=False)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    role: MemberRole = Field(
        sa_column=Column(
            SAEnum(MemberRole, name="memberRole", create_type=False),
            nullable=False,
            default="member",
        )
    )
    rsvpStatus: RsvpStatus = Field(
        sa_column=Column(
            SAEnum(RsvpStatus, name="rsvpStatus", create_type=False),
            nullable=False,
            default="pending",
        )
    )
    inviteToken: Optional[str] = None
    rating: Optional[int] = None
    invitedAt: datetime = Field(default_factory=datetime.utcnow)
    respondedAt: Optional[datetime] = None


# ---------------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------------


class PlanCreate(SQLModel):
    title: str
    placeId: Optional[UUID] = None
    ideaId: Optional[UUID] = None
    scheduledAt: Optional[datetime] = None
    estimatedMinutes: int = 60
    partySize: int = 1
    rawPrompt: Optional[str] = None
    taskNotes: str = ""


class PlanRead(SQLModel):
    id: UUID
    creatorId: UUID
    placeId: Optional[UUID] = None
    ideaId: Optional[UUID] = None
    title: str
    scheduledAt: Optional[datetime] = None
    status: PlanStatus
    shareCode: str
    rawPrompt: Optional[str] = None
    estimatedMinutes: int
    calendarEventId: Optional[str] = None
    partySize: int
    rating: Optional[int] = None
    taskNotes: str
    createdAt: datetime
    updatedAt: datetime
    members: list["PlanMemberRead"] = []
    placeName: Optional[str] = None


class PlanUpdate(SQLModel):
    title: Optional[str] = None
    placeId: Optional[UUID] = None
    scheduledAt: Optional[datetime] = None
    status: Optional[PlanStatus] = None
    estimatedMinutes: Optional[int] = None
    partySize: Optional[int] = None
    rating: Optional[int] = None
    taskNotes: Optional[str] = None


class PlanMemberRead(SQLModel):
    id: UUID
    planId: UUID
    userId: UUID
    role: MemberRole
    rsvpStatus: RsvpStatus
    inviteToken: Optional[str] = None
    rating: Optional[int] = None
    invitedAt: datetime
    respondedAt: Optional[datetime] = None
    firstName: Optional[str] = None
    lastName: Optional[str] = None


