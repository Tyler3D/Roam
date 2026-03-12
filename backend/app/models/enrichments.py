from datetime import datetime
from typing import Any, Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy import String


class EnrichmentModel(SQLModel, table=True):
    __tablename__ = "enrichments"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    refinedTitle: Optional[str] = None
    category: Optional[str] = None
    searchQuery: Optional[str] = None
    tags: Optional[list[str]] = Field(default=[], sa_column=Column(ARRAY(String)))
    estimatedMinutes: Optional[int] = None
    preference: Optional[str] = None
    aiEnriched: bool = Field(default=False)
    modelName: Optional[str] = None
    rawOutput: Optional[dict[str, Any]] = Field(default={}, sa_column=Column(JSONB))
    confidence: Optional[dict[str, Any]] = Field(default={}, sa_column=Column(JSONB))
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class EnrichmentRead(SQLModel):
    id: UUID
    refinedTitle: Optional[str] = None
    category: Optional[str] = None
    searchQuery: Optional[str] = None
    tags: list[str] = []
    estimatedMinutes: Optional[int] = None
    preference: Optional[str] = None
    aiEnriched: bool
    modelName: Optional[str] = None
    rawOutput: Optional[dict[str, Any]] = None
    confidence: Optional[dict[str, Any]] = None
    createdAt: datetime
