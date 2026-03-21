from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Field, SQLModel


class CollectionModel(SQLModel, table=True):
    __tablename__ = "collections"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    creatorId: UUID = Field(foreign_key="users.id", nullable=False, index=True)
    name: str = Field(default="")
    description: Optional[str] = None
    isPersonalDefault: bool = Field(default=False)
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class CollectionMemberModel(SQLModel, table=True):
    __tablename__ = "collection_members"

    collectionId: UUID = Field(foreign_key="collections.id", primary_key=True)
    userId: UUID = Field(foreign_key="users.id", primary_key=True)
    joinedAt: datetime = Field(default_factory=datetime.utcnow)


class CollectionIdeaModel(SQLModel, table=True):
    __tablename__ = "collection_ideas"

    collectionId: UUID = Field(foreign_key="collections.id", primary_key=True)
    ideaId: UUID = Field(foreign_key="ideas.id", primary_key=True)
    addedAt: datetime = Field(default_factory=datetime.utcnow)


class CollectionMemberPreview(SQLModel):
    userId: UUID
    firstName: str = ""
    lastName: str = ""
    photoUrl: Optional[str] = None


class CollectionRead(SQLModel):
    id: UUID
    creatorId: UUID
    name: str
    description: Optional[str] = None
    isPersonalDefault: bool
    createdAt: datetime
    memberPreview: list[CollectionMemberPreview] = Field(default_factory=list)


class CollectionCreate(SQLModel):
    name: str
    description: Optional[str] = None
    memberUserIds: list[UUID] = Field(default_factory=list)


class CollectionPatch(SQLModel):
    name: Optional[str] = None
    description: Optional[str] = None


class CollectionMemberAddBody(SQLModel):
    userId: UUID


class CollectionMapIdeaRead(SQLModel):
    id: UUID
    title: str
    notes: str = ""
    displayName: Optional[str] = None
    placeId: Optional[UUID] = None
    placeName: Optional[str] = None
    placeAddress: Optional[str] = None
    placeLatitude: Optional[float] = None
    placeLongitude: Optional[float] = None
    category: Optional[str] = None
    createdAt: datetime
    addedByUserId: UUID
    addedByFirstName: str = ""
    addedByLastName: str = ""
    addedByColorIndex: int = 0
