from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import Enum as SAEnum

from app.models.pipeline import PipelineResultRead


class IdeaStatus(str, Enum):
    captured = "captured"
    suggesting = "suggesting"
    ready = "ready"
    planned = "planned"


class IdeaWithPlanCountView(SQLModel, table=True):
    """Read-only view: ideas joined with COUNT(plans). Use for listing ideas with planCount."""
    __tablename__ = "ideas_with_plan_count"
    __table_args__ = {"info": {"is_view": True}}

    id: UUID = Field(primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    title: str = Field(nullable=False)
    notes: str = Field(default="")
    sourceUrl: str = Field(default="")
    displayName: Optional[str] = Field(default=None)
    placeId: Optional[UUID] = Field(default=None, foreign_key="places.id")
    savedReelId: Optional[UUID] = Field(default=None, foreign_key="saved_reels.id")
    status: IdeaStatus = Field(
        sa_column=Column(
            SAEnum(IdeaStatus, name="ideaStatus", create_type=False),
            nullable=False,
        )
    )
    planCount: int = Field(default=0)
    createdAt: datetime = Field()
    updatedAt: datetime = Field()


class IdeaModel(SQLModel, table=True):
    __tablename__ = "ideas"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    title: str = Field(nullable=False)
    notes: str = Field(default="")
    sourceUrl: str = Field(default="")
    displayName: Optional[str] = Field(default=None)
    placeId: Optional[UUID] = Field(default=None, foreign_key="places.id")
    savedReelId: Optional[UUID] = Field(default=None, foreign_key="saved_reels.id")
    status: IdeaStatus = Field(
        sa_column=Column(
            SAEnum(IdeaStatus, name="ideaStatus", create_type=False),
            nullable=False,
            default="captured",
        )
    )
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


class IdeaCreate(SQLModel):
    title: str
    notes: str = ""
    sourceUrl: str = ""
    displayName: Optional[str] = None
    collectionIds: list[UUID] = Field(
        default_factory=list,
        description="Additional shared collections only. Personal default is always linked; do not send it.",
    )


class IdeaSharedCollectionsAttach(SQLModel):
    """Add shared collection links for an existing idea (idempotent per collection)."""

    sharedCollectionIds: list[UUID] = Field(
        default_factory=list,
        description="Shared collections only. Personal default remains linked; do not send it.",
    )


class IdeaRead(SQLModel):
    id: UUID
    userId: UUID
    title: str
    notes: str
    sourceUrl: str
    displayName: Optional[str] = None
    placeId: Optional[UUID] = None
    savedReelId: Optional[UUID] = None
    status: IdeaStatus
    planCount: int = 0
    createdAt: datetime
    updatedAt: datetime
    pipelineResult: Optional[PipelineResultRead] = None
    placeName: Optional[str] = None
    placeLatitude: Optional[float] = None
    placeLongitude: Optional[float] = None
    googlePlaceId: Optional[str] = None
    collectionIds: list[UUID] = Field(
        default_factory=list,
        description="Collections this idea is in that the requesting user belongs to (personal default first).",
    )


class IdeaPageRead(SQLModel):
    """Paginated ideas list (GET /api/ideas with cursor + limit)."""

    items: list[IdeaRead] = Field(default_factory=list)
    nextCursor: Optional[str] = None
    hasMore: bool = False
    totalCount: Optional[int] = None


class IdeaUpdate(SQLModel):
    title: Optional[str] = None
    notes: Optional[str] = None
    sourceUrl: Optional[str] = None
    displayName: Optional[str] = None
    status: Optional[IdeaStatus] = None
    placeId: Optional[UUID] = None
