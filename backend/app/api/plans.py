import logging
import secrets
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlmodel import Session, select, col, or_

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Conflict, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.places import PlaceModel
from app.models.plans import (
    MemberRole,
    PlanMemberModel,
    PlanMemberRead,
    PlanModel,
    PlanRead,
    PlanUpdate,
    RsvpStatus,
)
from app.models.users import UserModel
from app.services.scheduling import suggest_time_slots
from app.services.invite import send_plan_invites, build_gcal_link, get_schedule_url

logger = logging.getLogger("roam.plans")
plansRouter = APIRouter()


@plansRouter.get("/plans", response_model=list[PlanRead])
def listPlans(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[PlanRead]:
    member_plan_ids = session.exec(
        select(PlanMemberModel.planId).where(PlanMemberModel.userId == user.id)
    ).all()

    plans = session.exec(
        select(PlanModel).where(
            or_(
                PlanModel.creatorId == user.id,
                col(PlanModel.id).in_(member_plan_ids),
            )
        ).order_by(col(PlanModel.createdAt).desc())
    ).all()

    results: list[PlanRead] = []
    for plan in plans:
        read = _build_plan_read(session, plan)
        results.append(read)
    return results


@plansRouter.get("/plans/{planId}", response_model=PlanRead)
def getPlan(
    planId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> PlanRead:
    plan = session.get(PlanModel, planId)
    if not plan:
        raise NotFound("Plan not found")

    is_member = session.exec(
        select(PlanMemberModel).where(
            PlanMemberModel.planId == planId,
            PlanMemberModel.userId == user.id,
        )
    ).first()
    if plan.creatorId != user.id and not is_member:
        raise Forbidden("Not your plan")

    return _build_plan_read(session, plan)


@plansRouter.patch("/plans/{planId}", response_model=PlanRead)
def updatePlan(
    planId: UUID,
    body: PlanUpdate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> PlanRead:
    plan = session.get(PlanModel, planId)
    if not plan:
        raise NotFound("Plan not found")
    if plan.creatorId != user.id:
        raise Forbidden("Only the creator can update the plan")

    update_data = body.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(plan, key, value)
    plan.updatedAt = datetime.utcnow()

    session.add(plan)
    commitAndRefresh(session, plan)

    if "scheduledAt" in update_data and plan.scheduledAt:
        _send_invites_for_plan(session, plan)

    return _build_plan_read(session, plan)


@plansRouter.post("/plans/{planId}/suggest-slots")
def suggestSlots(
    planId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[dict]:
    plan = session.get(PlanModel, planId)
    if not plan:
        raise NotFound("Plan not found")

    preference = "any"

    opening_hours = None
    if plan.placeId:
        place = session.get(PlaceModel, plan.placeId)
        if place and place.openingHours:
            opening_hours = place.openingHours

    return suggest_time_slots(
        preference=preference,
        estimated_minutes=plan.estimatedMinutes,
        opening_hours=opening_hours,
    )


@plansRouter.post("/plans/{planId}/calendar")
def createCalendarEvent(
    planId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> dict:
    plan = session.get(PlanModel, planId)
    if not plan:
        raise NotFound("Plan not found")
    if plan.creatorId != user.id:
        raise Forbidden("Only the creator can create a calendar event")
    if not plan.scheduledAt:
        raise BadRequest("Plan must have a scheduled time")

    location = None
    if plan.placeId:
        place = session.get(PlaceModel, plan.placeId)
        if place:
            location = f"{place.name}, {place.address}" if place.address else place.name

    gcal_link = build_gcal_link(
        title=plan.title,
        start_time=plan.scheduledAt,
        duration_minutes=plan.estimatedMinutes,
        location=location,
    )
    schedule_url = get_schedule_url(plan.shareCode)

    return {
        "gcalLink": gcal_link,
        "scheduleUrl": schedule_url,
        "planId": str(plan.id),
    }


class AddMemberRequest(BaseModel):
    userId: UUID


@plansRouter.post("/plans/{planId}/members", response_model=PlanRead)
def addPlanMember(
    planId: UUID,
    body: AddMemberRequest,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> PlanRead:
    plan = session.get(PlanModel, planId)
    if not plan:
        raise NotFound("Plan not found")
    if plan.creatorId != user.id:
        raise Forbidden("Only the creator can add members")

    if body.userId == user.id:
        raise BadRequest("Cannot add yourself")

    target = session.get(UserModel, body.userId)
    if not target:
        raise NotFound("User not found")

    existing = session.exec(
        select(PlanMemberModel).where(
            PlanMemberModel.planId == planId,
            PlanMemberModel.userId == body.userId,
        )
    ).first()
    if existing:
        raise Conflict("User is already a member")

    member = PlanMemberModel(
        planId=plan.id,
        userId=body.userId,
        role=MemberRole.member,
        rsvpStatus=RsvpStatus.pending,
        inviteToken=secrets.token_urlsafe(12),
    )
    session.add(member)
    commitAndRefresh(session, plan)

    _send_invites_for_plan(session, plan)

    return _build_plan_read(session, plan)


def _build_plan_read(session: Session, plan: PlanModel) -> PlanRead:
    read = PlanRead.model_validate(plan)

    members = session.exec(
        select(PlanMemberModel).where(PlanMemberModel.planId == plan.id)
    ).all()
    member_reads = []
    for m in members:
        mr = PlanMemberRead.model_validate(m)
        member_user = session.get(UserModel, m.userId)
        if member_user:
            mr.firstName = member_user.firstName
            mr.lastName = member_user.lastName
        member_reads.append(mr)
    read.members = member_reads

    if plan.placeId:
        place = session.get(PlaceModel, plan.placeId)
        if place:
            read.placeName = place.name

    return read


def _send_invites_for_plan(session: Session, plan: PlanModel) -> None:
    members = session.exec(
        select(PlanMemberModel).where(PlanMemberModel.planId == plan.id)
    ).all()

    place_name = None
    place_address = None
    if plan.placeId:
        place = session.get(PlaceModel, plan.placeId)
        if place:
            place_name = place.name
            place_address = place.address

    member_data = []
    for m in members:
        user = session.get(UserModel, m.userId)
        if user:
            member_data.append({
                "userId": str(user.id),
                "email": user.email,
                "phone": user.phone,
                "firstName": user.firstName,
            })

    send_plan_invites(
        plan_title=plan.title,
        scheduled_at=plan.scheduledAt,
        estimated_minutes=plan.estimatedMinutes,
        place_name=place_name,
        place_address=place_address,
        share_code=plan.shareCode,
        members=member_data,
    )
