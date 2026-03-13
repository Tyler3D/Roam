from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Column, Field, SQLModel
from sqlalchemy.dialects.postgresql import JSONB


class UserModel(SQLModel, table=True):
    __tablename__ = "users"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    firebaseUid: Optional[str] = Field(default=None, unique=True)
    username: Optional[str] = Field(default=None, unique=True)
    email: Optional[str] = Field(default=None, unique=True)
    firstName: str = Field(default="")
    lastName: str = Field(default="")
    phone: Optional[str] = None
    photoUrl: Optional[str] = None
    city: Optional[str] = None
    interestTags: Optional[list] = Field(default=[], sa_column=Column(JSONB))
    isActive: bool = Field(default=False)
    isOnboarded: bool = Field(default=False)
    isGuestUser: bool = Field(default=False)
    emailVerified: bool = Field(default=False)
    createdAt: datetime = Field(default_factory=datetime.utcnow)


class UserCreate(SQLModel):
    username: Optional[str] = None
    email: Optional[str] = None
    firstName: str = ""
    lastName: str = ""
    phone: Optional[str] = None
    photoUrl: Optional[str] = None


class UserRead(SQLModel):
    id: UUID
    firebaseUid: Optional[str] = None
    username: Optional[str] = None
    email: Optional[str] = None
    firstName: str
    lastName: str
    phone: Optional[str] = None
    photoUrl: Optional[str] = None
    city: Optional[str] = None
    isActive: bool
    isOnboarded: bool
    isGuestUser: bool
    emailVerified: bool
    createdAt: datetime


class UserUpdate(SQLModel):
    firstName: Optional[str] = None
    lastName: Optional[str] = None
    phone: Optional[str] = None
    photoUrl: Optional[str] = None
    city: Optional[str] = None
    isOnboarded: Optional[bool] = None
