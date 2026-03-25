from datetime import datetime
from uuid import UUID, uuid4

from sqlmodel import Field, SQLModel, UniqueConstraint


class UserFeatureFlagModel(SQLModel, table=True):
    """Per-user feature flags."""
    __tablename__ = "user_feature_flags"
    __table_args__ = (
        UniqueConstraint("user_id", "flag_name", name="uq_uff_user_flag"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    user_id: UUID = Field(foreign_key="users.id", nullable=False, index=True)
    flag_name: str = Field(nullable=False, index=True)
    enabled: bool = Field(default=True, nullable=False)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# ── DTOs ──

class FeatureFlagRead(SQLModel):
    flagName: str
    enabled: bool


class FeatureFlagUpdate(SQLModel):
    enabled: bool
