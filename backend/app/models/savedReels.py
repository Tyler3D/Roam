from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel, UniqueConstraint
from sqlalchemy import CheckConstraint, Enum as SAEnum, String
from sqlalchemy.dialects.postgresql import JSONB

from app.models.ideas import IdeaStatus


class SavedReelStatus(str, Enum):
    processing = "processing"
    needs_review = "needs_review"
    promoted = "promoted"
    failed = "failed"


class SavedReelModel(SQLModel, table=True):
    __tablename__ = "saved_reels"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False, index=True)
    jobId: UUID = Field(foreign_key="reel_ingestion_jobs.id", nullable=False, unique=True)
    thumbnailObjectPath: Optional[str] = None
    reelUrl: str = Field(nullable=False)
    title: str = Field(default="")
    status: SavedReelStatus = Field(
        sa_column=Column(
            SAEnum(SavedReelStatus, name="savedReelStatus", create_type=False),
            nullable=False,
            default=SavedReelStatus.processing,
        )
    )
    # How many times retry-ingest was accepted (cap enforced server-side).
    ingestRetryCount: int = Field(default=0, nullable=False)
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


class ReelIngestCandidateModel(SQLModel, table=True):
    __tablename__ = "reel_ingest_candidates"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    savedReelId: UUID = Field(foreign_key="saved_reels.id", nullable=False, index=True)
    sortIndex: int = Field(default=0)
    llmRawOutput: dict[str, Any] = Field(default_factory=dict, sa_column=Column("llmRawOutput", JSONB))
    # Vague LLM location ("Brooklyn NY"); set at ingest, never overwritten by user place edits.
    llmDetectedInLabel: Optional[str] = Field(
        default=None,
        sa_column=Column("llmDetectedInLabel", String(500), nullable=True),
    )
    resolvedPlaceId: Optional[UUID] = Field(default=None, foreign_key="places.id")
    promotedIdeaId: Optional[UUID] = Field(default=None, foreign_key="ideas.id")
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class ReelCandidateUserPlaceModel(SQLModel, table=True):
    """Per-user confirmed place for a reel candidate (join table)."""
    __tablename__ = "reel_candidate_user_places"
    __table_args__ = (
        UniqueConstraint("candidate_id", "user_id", name="uq_rcup_candidate_user"),
        CheckConstraint("source IN ('pipeline', 'user')", name="ck_rcup_source"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    candidate_id: UUID = Field(foreign_key="reel_ingest_candidates.id", nullable=False, index=True)
    user_id: UUID = Field(foreign_key="users.id", nullable=False, index=True)
    place_id: Optional[UUID] = Field(default=None, foreign_key="places.id")
    place_name: Optional[str] = None
    place_address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    maps_query: Optional[str] = None
    source: str = Field(default="user")
    confirmed_at: datetime = Field(default_factory=datetime.utcnow)


class SavedReelListItem(SQLModel):
    id: UUID
    jobId: UUID
    reelUrl: str
    title: str
    status: SavedReelStatus
    thumbnailSignedUrl: Optional[str] = None
    createdAt: datetime
    updatedAt: datetime


class SavedReelIdeaSummary(SQLModel):
    id: UUID
    title: str
    status: IdeaStatus
    placeId: Optional[UUID] = None
    placeName: Optional[str] = None


class ReelIngestCandidateRead(SQLModel):
    id: UUID
    savedReelId: UUID
    sortIndex: int
    previewTitle: str = ""
    isSynthetic: bool = False
    resolvedPlaceId: Optional[UUID] = None
    promotedIdeaId: Optional[UUID] = None
    createdAt: datetime
    resolvedPlaceName: Optional[str] = None
    previewDescription: str = ""
    category: str = ""
    placeAddress: Optional[str] = None
    # LLM vague text, else pipeline place address/name; never user override (UI "Detected in …").
    detectedInLabel: Optional[str] = None
    mapsQuery: Optional[str] = None
    confidence: Optional[float] = None
    placeLatitude: Optional[float] = None
    placeLongitude: Optional[float] = None


class SavedReelDetailRead(SQLModel):
    id: UUID
    jobId: UUID
    reelUrl: str
    title: str
    status: SavedReelStatus
    thumbnailSignedUrl: Optional[str] = None
    ingestRetryCount: int = 0
    jobStatus: str
    jobError: Optional[str] = None
    candidates: list[ReelIngestCandidateRead] = Field(default_factory=list)
    ideas: list[SavedReelIdeaSummary] = Field(default_factory=list)
    ideaIds: list[UUID] = Field(default_factory=list)
    createdAt: datetime
    updatedAt: datetime


class ReelPromotionItem(SQLModel):
    candidateId: UUID
    title: Optional[str] = None
    mapsQuery: Optional[str] = None
    placeAddress: Optional[str] = None
    category: Optional[str] = None
    placeId: Optional[UUID] = None


class PromoteReelRequest(SQLModel):
    promotions: list[ReelPromotionItem] = Field(default_factory=list)
    collectionIds: list[UUID] = Field(
        default_factory=list,
        description="Additional shared collections only. Personal default is always linked; do not send it.",
    )


class PromoteReelResponse(SQLModel):
    ideaIds: list[UUID] = Field(default_factory=list)
    reelStatus: SavedReelStatus


class ReelsSummaryRead(SQLModel):
    needsReviewCount: int = 0


class UpdateCandidatePlaceBody(SQLModel):
    """Body for PATCH /reels/{reelId}/candidates/{candidateId}/place."""
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    mapsQuery: Optional[str] = None


class UpdateCandidatePlaceRead(SQLModel):
    """Response after confirming a candidate place."""
    candidateId: UUID
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    mapsQuery: Optional[str] = None
    source: str = "user"


class CreateIdeaOnReelBody(SQLModel):
    title: str
    notes: str = ""
    placeId: Optional[UUID] = None
    collectionIds: list[UUID] = Field(
        default_factory=list,
        description="Additional shared collections only. Personal default is always linked; do not send it.",
    )
