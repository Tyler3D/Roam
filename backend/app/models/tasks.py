"""Task models and schemas for plan tasks."""

from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from pydantic import BaseModel
from sqlmodel import Field, SQLModel


class PlanTaskModel(SQLModel, table=True):
    __tablename__ = "plan_tasks"

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    planId: UUID = Field(foreign_key="plans.id", nullable=False)
    assigneeId: UUID = Field(foreign_key="plan_members.id", nullable=False)
    description: str = Field(nullable=False)
    isCompleted: bool = Field(default=False)
    createdAt: datetime = Field(default_factory=datetime.utcnow)
    completedAt: Optional[datetime] = None


class TaskRead(BaseModel):
    id: UUID
    planId: UUID
    assigneeId: UUID
    assigneeFirstName: str = ""
    description: str
    isCompleted: bool
    createdAt: datetime
    completedAt: Optional[datetime] = None


class TaskCreate(BaseModel):
    description: str
    assigneeId: UUID


class TaskUpdate(BaseModel):
    isCompleted: Optional[bool] = None
    description: Optional[str] = None
    assigneeId: Optional[UUID] = None
