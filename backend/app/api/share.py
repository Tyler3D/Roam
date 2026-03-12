import logging
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlmodel import Session, select
from typing import Optional

from app.common.backendErrors import BadRequest, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.friendships import FriendshipModel, FriendshipStatus
from app.models.notifications import NotificationModel, NotificationType
from app.models.places import PlaceModel
from app.models.plans import (
    MemberRole,
    PlanMemberModel,
    PlanMemberRead,
    PlanModel,
    PlanRead,
    RsvpStatus,
)
from app.models.users import UserModel
from app.services.invite import build_gcal_link, get_schedule_url, send_single_invite

logger = logging.getLogger("roam.share")
shareRouter = APIRouter()


class RsvpRequest(BaseModel):
    firstName: str
    lastName: str
    phone: Optional[str] = None
    email: Optional[str] = None


class RsvpResponse(BaseModel):
    success: bool
    memberId: UUID
    userId: UUID
    gcalLink: Optional[str] = None
    scheduleUrl: Optional[str] = None


@shareRouter.get("/share/{shareCode}", response_model=PlanRead)
def getSharedPlan(
    shareCode: str,
    session: Session = Depends(getSession),
) -> PlanRead:
    plan = session.exec(
        select(PlanModel).where(PlanModel.shareCode == shareCode)
    ).first()
    if not plan:
        raise NotFound("Plan not found")

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


@shareRouter.post("/share/{shareCode}/rsvp", response_model=RsvpResponse)
def rsvpToSharedPlan(
    shareCode: str,
    body: RsvpRequest,
    session: Session = Depends(getSession),
) -> RsvpResponse:
    if not body.phone and not body.email:
        raise BadRequest("Phone or email is required")
    if not body.firstName.strip():
        raise BadRequest("First name is required")

    plan = session.exec(
        select(PlanModel).where(PlanModel.shareCode == shareCode)
    ).first()
    if not plan:
        raise NotFound("Plan not found")

    user = _find_or_create_external_user(session, body)

    existing_member = session.exec(
        select(PlanMemberModel).where(
            PlanMemberModel.planId == plan.id,
            PlanMemberModel.userId == user.id,
        )
    ).first()

    if existing_member:
        existing_member.rsvpStatus = RsvpStatus.accepted
        session.add(existing_member)
        commitAndRefresh(session, existing_member)
        member_id = existing_member.id
    else:
        member = PlanMemberModel(
            planId=plan.id,
            userId=user.id,
            role=MemberRole.member,
            rsvpStatus=RsvpStatus.accepted,
        )
        session.add(member)
        session.flush()
        member_id = member.id

    _ensure_friendship(session, plan.creatorId, user.id)

    _notify_plan_creator(
        session,
        creator_id=plan.creatorId,
        plan_id=plan.id,
        plan_title=plan.title,
        rsvp_name=f"{body.firstName.strip()} {body.lastName.strip()}".strip(),
    )

    session.commit()
    session.refresh(user)

    gcal_link = None
    schedule_url = get_schedule_url(plan.shareCode)

    if plan.scheduledAt and user.email:
        place_name = None
        if plan.placeId:
            place = session.get(PlaceModel, plan.placeId)
            if place:
                place_name = place.name
        gcal_link = build_gcal_link(
            title=plan.title,
            start_time=plan.scheduledAt,
            duration_minutes=plan.estimatedMinutes,
            location=place_name,
        )

    if plan.scheduledAt:
        place_name = None
        if plan.placeId:
            place = session.get(PlaceModel, plan.placeId)
            if place:
                place_name = place.name
        send_single_invite(
            plan_title=plan.title,
            scheduled_at=plan.scheduledAt,
            estimated_minutes=plan.estimatedMinutes,
            place_name=place_name,
            share_code=plan.shareCode,
            email=user.email,
            phone=user.phone,
            first_name=user.firstName,
        )

    return RsvpResponse(
        success=True,
        memberId=member_id,
        userId=user.id,
        gcalLink=gcal_link,
        scheduleUrl=schedule_url,
    )


def _find_or_create_external_user(session: Session, body: RsvpRequest) -> UserModel:
    if body.email:
        existing = session.exec(
            select(UserModel).where(UserModel.email == body.email)
        ).first()
        if existing:
            return existing

    if body.phone:
        existing = session.exec(
            select(UserModel).where(UserModel.phone == body.phone)
        ).first()
        if existing:
            return existing

    user = UserModel(
        firstName=body.firstName.strip(),
        lastName=body.lastName.strip(),
        email=body.email,
        phone=body.phone,
        isExternal=True,
        isActive=True,
    )
    session.add(user)
    session.flush()
    return user


def _ensure_friendship(session: Session, creator_id: UUID, external_user_id: UUID) -> None:
    if creator_id == external_user_id:
        return

    from sqlmodel import or_
    existing = session.exec(
        select(FriendshipModel).where(
            or_(
                (FriendshipModel.requesterId == creator_id)
                & (FriendshipModel.addresseeId == external_user_id),
                (FriendshipModel.requesterId == external_user_id)
                & (FriendshipModel.addresseeId == creator_id),
            )
        )
    ).first()

    if existing:
        if existing.status != FriendshipStatus.accepted:
            existing.status = FriendshipStatus.accepted
            session.add(existing)
        return

    friendship = FriendshipModel(
        requesterId=creator_id,
        addresseeId=external_user_id,
        status=FriendshipStatus.accepted,
    )
    session.add(friendship)


def _notify_plan_creator(
    session: Session,
    creator_id: UUID,
    plan_id: UUID,
    plan_title: str,
    rsvp_name: str,
) -> None:
    notification = NotificationModel(
        userId=creator_id,
        type=NotificationType.rsvp_accepted,
        planId=plan_id,
        title=f"{rsvp_name} joined your plan",
        body=f"{rsvp_name} RSVP'd to {plan_title}",
    )
    session.add(notification)
