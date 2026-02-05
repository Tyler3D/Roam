from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Field, SQLModel


class UserModel(SQLModel, table=True):
    __tablename__ = "users"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    firebaseUid: str = Field(index=True, unique=True)
    username: str = Field(index=True, unique=True)
    email: str = Field(index=True, unique=True)
    displayName: Optional[str] = None
    photoUrl: Optional[str] = None
    isActive: bool = Field(default=False)
    emailVerified: bool = Field(default=False)
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class UserCreate(SQLModel):
    username: str
    email: Optional[str] = None
    displayName: Optional[str] = None
    photoUrl: Optional[str] = None


class UserRead(SQLModel):
    id: UUID
    firebaseUid: str
    username: str
    email: str
    displayName: Optional[str] = None
    photoUrl: Optional[str] = None
    isActive: bool
    emailVerified: bool
    createdAt: datetime

