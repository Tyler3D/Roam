from datetime import datetime
from typing import Any, Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy.dialects.postgresql import JSONB


class PipelineResultModel(SQLModel, table=True):
    __tablename__ = "pipeline_results"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    ideaId: Optional[UUID] = Field(default=None, foreign_key="ideas.id")
    jobId: Optional[UUID] = Field(default=None, foreign_key="reel_ingestion_jobs.id")
    source: str = Field(nullable=False)
    refinedTitle: Optional[str] = None
    category: Optional[str] = None
    estimatedMinutes: Optional[int] = None
    modelName: Optional[str] = None
    rawOutput: Optional[dict[str, Any]] = Field(default={}, sa_column=Column(JSONB))
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class PlaceSuggestionModel(SQLModel, table=True):
    __tablename__ = "place_suggestions"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    resultId: UUID = Field(foreign_key="pipeline_results.id", nullable=False)
    placeId: Optional[UUID] = Field(default=None, foreign_key="places.id")
    rawName: Optional[str] = None
    confidence: Optional[float] = None
    isSelected: bool = Field(default=False)
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class PlaceSuggestionRead(SQLModel):
    id: UUID
    resultId: UUID
    placeId: Optional[UUID] = None
    rawName: Optional[str] = None
    confidence: Optional[float] = None
    isSelected: bool
    createdAt: datetime
    placeName: Optional[str] = None


class PlaceSuggestionUpdate(SQLModel):
    isSelected: Optional[bool] = None


class PipelineResultRead(SQLModel):
    id: UUID
    ideaId: Optional[UUID] = None
    jobId: Optional[UUID] = None
    source: str
    refinedTitle: Optional[str] = None
    category: Optional[str] = None
    estimatedMinutes: Optional[int] = None
    modelName: Optional[str] = None
    rawOutput: Optional[dict[str, Any]] = None
    createdAt: datetime
    placeSuggestions: list[PlaceSuggestionRead] = []
