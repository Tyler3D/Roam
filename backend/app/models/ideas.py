from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import Enum as SAEnum

from app.models.enrichments import EnrichmentRead


class IdeaStatus(str, Enum):
    captured = "captured"
    suggesting = "suggesting"
    ready = "ready"
    planned = "planned"


class IdeaModel(SQLModel, table=True):
    __tablename__ = "ideas"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    title: str = Field(nullable=False)
    notes: str = Field(default="")
    savedLink: str = Field(default="")
    placeId: Optional[UUID] = Field(default=None, foreign_key="places.id")
    enrichmentId: Optional[UUID] = Field(default=None, foreign_key="enrichments.id")
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
    savedLink: str = ""


class IdeaRead(SQLModel):
    id: UUID
    userId: UUID
    title: str
    notes: str
    savedLink: str
    placeId: Optional[UUID] = None
    enrichmentId: Optional[UUID] = None
    status: IdeaStatus
    createdAt: datetime
    updatedAt: datetime
    enrichment: Optional[EnrichmentRead] = None
    placeName: Optional[str] = None


class IdeaUpdate(SQLModel):
    title: Optional[str] = None
    notes: Optional[str] = None
    savedLink: Optional[str] = None
    status: Optional[IdeaStatus] = None
