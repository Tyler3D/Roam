from datetime import datetime
from uuid import UUID, uuid4

from sqlmodel import Field, SQLModel


class UserOAuthTokenModel(SQLModel, table=True):
    __tablename__ = "user_oauth_tokens"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    userId: UUID = Field(foreign_key="users.id", nullable=False)
    provider: str = Field(nullable=False)
    encryptedAccessToken: str = Field(nullable=False)
    encryptedRefreshToken: str | None = None
    expiresAt: datetime | None = None
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    updatedAt: datetime = Field(default_factory=datetime.utcnow)


class OAuthTokenUpsert(SQLModel):
    """Payload for storing tokens (plaintext; encrypted before storage)."""

    accessToken: str
    refreshToken: str | None = None
    expiresAt: datetime | None = None
