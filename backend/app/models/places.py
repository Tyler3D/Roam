from datetime import datetime
from typing import Any, Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy import String
from sqlalchemy.dialects.postgresql import ARRAY, JSONB


class PlaceModel(SQLModel, table=True):
    __tablename__ = "places"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    googlePlaceId: Optional[str] = Field(default=None, unique=True)
    name: str = Field(nullable=False)
    address: Optional[str] = None
    city: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    category: Optional[str] = None
    openingHours: Optional[list[Any]] = Field(default=[], sa_column=Column(JSONB))
    placeTypes: Optional[list[str]] = Field(default=[], sa_column=Column(ARRAY(String)))
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class PlaceRead(SQLModel):
    id: UUID
    googlePlaceId: Optional[str] = None
    name: str
    address: Optional[str] = None
    city: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    category: Optional[str] = None
    openingHours: Optional[list[Any]] = None
    placeTypes: Optional[list[str]] = None
    createdAt: datetime
    estimatedMinutes: Optional[int] = None
