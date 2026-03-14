"""Task API — plan-scoped tasks."""

import logging
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.plans import PlanMemberModel, PlanModel
from app.models.tasks import PlanTaskModel, TaskRead, TaskCreate, TaskUpdate
from app.models.users import UserModel
from app.models.notifications import NotificationModel, NotificationType

logger = logging.getLogger("roam.tasks")
tasksRouter = APIRouter()


def _ensure_plan_member(session: Session, plan_id: UUID, user_id: UUID) -> PlanModel:
    plan = session.get(PlanModel, plan_id)
    if not plan:
        raise NotFound("Plan not found")
    is_member = session.exec(
        select(PlanMemberModel).where(
            PlanMemberModel.planId == plan_id,
            PlanMemberModel.userId == user_id,
        )
    ).first()
    if plan.creatorId != user_id and not is_member:
        raise Forbidden("Not your plan")
    return plan


def _build_task_read(session: Session, task: PlanTaskModel) -> TaskRead:
    read = TaskRead.model_validate(task)
    assignee = session.get(PlanMemberModel, task.assigneeId)
    if assignee:
        assignee_user = session.get(UserModel, assignee.userId)
        if assignee_user:
            read.assigneeFirstName = assignee_user.firstName or ""
    return read


@tasksRouter.get("/tasks/{planId}", response_model=list[TaskRead])
def listTasks(
    planId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[TaskRead]:
    _ensure_plan_member(session, planId, user.id)
    tasks = session.exec(
        select(PlanTaskModel)
        .where(PlanTaskModel.planId == planId)
        .order_by(PlanTaskModel.createdAt)
    ).all()
    return [_build_task_read(session, t) for t in tasks]


@tasksRouter.post("/tasks/{planId}", response_model=TaskRead)
def createTask(
    planId: UUID,
    body: TaskCreate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> TaskRead:
    plan = _ensure_plan_member(session, planId, user.id)
    assignee = session.get(PlanMemberModel, body.assigneeId)
    if not assignee or assignee.planId != planId:
        raise BadRequest("Assignee must be a plan member")
    task = PlanTaskModel(
        planId=planId,
        assigneeId=body.assigneeId,
        description=body.description.strip(),
    )
    session.add(task)
    session.flush()
    assigner_name = user.firstName or "Someone"
    notification = NotificationModel(
        userId=assignee.userId,
        type=NotificationType.task_assigned,
        planId=planId,
        title=f"{assigner_name} assigned you a task: {task.description}",
    )
    session.add(notification)
    commitAndRefresh(session, task)
    return _build_task_read(session, task)


@tasksRouter.patch("/tasks/{planId}/{taskId}", response_model=TaskRead)
def updateTask(
    planId: UUID,
    taskId: UUID,
    body: TaskUpdate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> TaskRead:
    plan = _ensure_plan_member(session, planId, user.id)
    task = session.get(PlanTaskModel, taskId)
    if not task or task.planId != planId:
        raise NotFound("Task not found")
    assignee = session.get(PlanMemberModel, task.assigneeId)
    is_organizer = plan.creatorId == user.id
    is_assignee = assignee and assignee.userId == user.id
    if not is_organizer and not is_assignee:
        raise Forbidden("Only organizer or assignee can update this task")
    task.isCompleted = body.isCompleted
    task.completedAt = datetime.utcnow() if body.isCompleted else None
    session.add(task)
    commitAndRefresh(session, task)
    return _build_task_read(session, task)


@tasksRouter.delete("/tasks/{planId}/{taskId}", status_code=204)
def deleteTask(
    planId: UUID,
    taskId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    plan = _ensure_plan_member(session, planId, user.id)
    task = session.get(PlanTaskModel, taskId)
    if not task or task.planId != planId:
        raise NotFound("Task not found")
    assignee = session.get(PlanMemberModel, task.assigneeId)
    is_organizer = plan.creatorId == user.id
    is_assignee = assignee and assignee.userId == user.id
    if not is_organizer and not is_assignee:
        raise Forbidden("Only organizer or assignee can delete this task")
    session.delete(task)
    session.commit()
