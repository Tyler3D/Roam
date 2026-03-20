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
    __tablename__ = "reel_ingestion_jobs"
    __table_args__ = (
        UniqueConstraint("userId", "reelUrl", name="unique_user_reel"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False, index=True)
    ideaId: Optional[UUID] = Field(default=None, foreign_key="ideas.id", nullable=True)
    reelUrl: str = Field(nullable=False)
    shareText: Optional[str] = None
    reelTitle: Optional[str] = None
    ogDescription: Optional[str] = None
    ogKeywords: Optional[str] = None
    status: JobStatus = Field(
        sa_column=Column(SAEnum(JobStatus, name="jobStatus", create_type=False), nullable=False, default="processing")
    )
    error: Optional[str] = None
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Pydantic schemas for API request / response
# ---------------------------------------------------------------------------

class IngestionJobCreate(SQLModel):
    reelUrl: str
    shareText: Optional[str] = None
    reelTitle: Optional[str] = None
    ogDescription: Optional[str] = None
    ogKeywords: Optional[str] = None


class IngestionJobRead(SQLModel):
    id: UUID
    userId: UUID
    ideaId: Optional[UUID] = None
    reelUrl: str
    shareText: Optional[str] = None
    reelTitle: Optional[str] = None
    ogDescription: Optional[str] = None
    ogKeywords: Optional[str] = None
    status: JobStatus
    error: Optional[str] = None
    createdAt: datetime
    updatedAt: datetime


