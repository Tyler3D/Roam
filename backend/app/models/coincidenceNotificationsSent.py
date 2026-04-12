from datetime import datetime
from uuid import UUID, uuid4

from sqlmodel import Field, SQLModel


class CoincidenceNotificationSentModel(SQLModel, table=True):
    __tablename__ = "coincidence_notifications_sent"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    placeId: UUID = Field(foreign_key="places.id", nullable=False)
    sentAt: datetime = Field(default_factory=datetime.utcnow)
