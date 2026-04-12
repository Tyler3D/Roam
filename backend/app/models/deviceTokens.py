from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from sqlmodel import Field, SQLModel


class DeviceTokenModel(SQLModel, table=True):
    __tablename__ = "device_tokens"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    fcmToken: str = Field(nullable=False)
    platform: str = Field(default="ios")
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


class DeviceTokenCreate(SQLModel):
    fcmToken: str
    platform: str = "ios"


class DeviceTokenRead(SQLModel):
    id: UUID
    userId: UUID
    fcmToken: str
    platform: str
    createdAt: datetime
