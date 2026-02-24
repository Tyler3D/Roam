from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import CheckConstraint, Enum as SAEnum


class VisitStatus(str, Enum):
    want = "want"
    been = "been"


class PinSource(str, Enum):
    reel = "reel"
    manual = "manual"


class ActivityPinModel(SQLModel, table=True):
    __tablename__ = "activity_pins"
    __table_args__ = (
        CheckConstraint('"rating" >= 1 AND "rating" <= 5', name="rating_range"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False, index=True)
    extractionId: Optional[UUID] = Field(default=None, foreign_key="extractions.id")
    title: str = Field(nullable=False)
    category: Optional[str] = Field(default=None, index=True)
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    googlePlaceId: Optional[str] = None
    rating: Optional[int] = None
    visitStatus: VisitStatus = Field(
        sa_column=Column(SAEnum(VisitStatus, name="visitStatus", create_type=False), nullable=False, default="want")
    )
    notes: Optional[str] = None
    thumbnailUrl: Optional[str] = None
    reelUrl: Optional[str] = None
    source: PinSource = Field(
        sa_column=Column(SAEnum(PinSource, name="pinSource", create_type=False), nullable=False, default="reel")
    )
    lastInteractedAt: Optional[datetime] = None
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Pydantic schemas for API request / response
# ---------------------------------------------------------------------------

class ActivityPinCreate(SQLModel):
    extractionId: Optional[UUID] = None
    title: str
    category: Optional[str] = None
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    googlePlaceId: Optional[str] = None
    rating: Optional[int] = Field(default=None, ge=1, le=5)
    visitStatus: VisitStatus = VisitStatus.want
    notes: Optional[str] = None
    thumbnailUrl: Optional[str] = None
    reelUrl: Optional[str] = None
    source: PinSource = PinSource.reel


class ActivityPinRead(SQLModel):
    id: UUID
    userId: UUID
    extractionId: Optional[UUID] = None
    title: str
    category: Optional[str] = None
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    googlePlaceId: Optional[str] = None
    rating: Optional[int] = None
    visitStatus: VisitStatus
    notes: Optional[str] = None
    thumbnailUrl: Optional[str] = None
    reelUrl: Optional[str] = None
    source: PinSource
    lastInteractedAt: Optional[datetime] = None
    createdAt: datetime
    updatedAt: datetime


class ActivityPinUpdate(SQLModel):
    title: Optional[str] = None
    category: Optional[str] = None
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    googlePlaceId: Optional[str] = None
    rating: Optional[int] = Field(default=None, ge=1, le=5)
    visitStatus: Optional[VisitStatus] = None
    notes: Optional[str] = None
    thumbnailUrl: Optional[str] = None
