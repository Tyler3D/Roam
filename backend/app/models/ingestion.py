from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import Enum as SAEnum, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB


class JobStatus(str, Enum):
    processing = "processing"
    done = "done"
    failed = "failed"


class IngestionJobModel(SQLModel, table=True):
    __tablename__ = "ingestion_jobs"
    __table_args__ = (
        UniqueConstraint("userId", "reelUrl", name="unique_user_reel"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False, index=True)
    reelUrl: str = Field(nullable=False)
    shareText: Optional[str] = None
    lpTitle: Optional[str] = None
    ogDescription: Optional[str] = None
    ogKeywords: Optional[str] = None
    status: JobStatus = Field(
        sa_column=Column(SAEnum(JobStatus, name="jobStatus", create_type=False), nullable=False, default="processing")
    )
    error: Optional[str] = None
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


class ExtractionModel(SQLModel, table=True):
    __tablename__ = "extractions"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    jobId: UUID = Field(foreign_key="ingestion_jobs.id", nullable=False, index=True)
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    category: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    googlePlaceId: Optional[str] = None
    confidence: Optional[float] = None
    rawLlmOutput: Optional[dict[str, Any]] = Field(default=None, sa_column=Column(JSONB))
    createdAt: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Pydantic schemas for API request / response
# ---------------------------------------------------------------------------

class IngestionJobCreate(SQLModel):
    reelUrl: str
    shareText: Optional[str] = None
    lpTitle: Optional[str] = None
    ogDescription: Optional[str] = None
    ogKeywords: Optional[str] = None


class IngestionJobRead(SQLModel):
    id: UUID
    userId: UUID
    reelUrl: str
    shareText: Optional[str] = None
    lpTitle: Optional[str] = None
    ogDescription: Optional[str] = None
    ogKeywords: Optional[str] = None
    status: JobStatus
    error: Optional[str] = None
    createdAt: datetime
    updatedAt: datetime


class ExtractionRead(SQLModel):
    id: UUID
    jobId: UUID
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    category: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    googlePlaceId: Optional[str] = None
    confidence: Optional[float] = None
    createdAt: datetime
