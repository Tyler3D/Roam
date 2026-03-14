import logging
import secrets
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlmodel import Session, select, col

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.ideas import IdeaCreate, IdeaModel, IdeaRead, IdeaUpdate, IdeaStatus, IdeaWithPlanCountView
from app.models.pipeline import PipelineResultModel, PipelineResultRead, PlaceSuggestionModel, PlaceSuggestionRead
from app.models.places import PlaceModel
from app.models.plans import (
    MemberRole,
    PlanMemberModel,
    PlanMemberRead,
    PlanModel,
    PlanRead,
    PlanStatus,
    RsvpStatus,
)
from app.models.users import UserModel
from app.models.friendships import FriendshipModel, FriendshipStatus
from app.models.notifications import NotificationModel, NotificationType
from app.services.interpret import interpret_with_openai
from app.services.places import search_google_places
from app.services.scheduling import suggest_time_slots

logger = logging.getLogger("roam.ideas")
ideasRouter = APIRouter()


def _get_latest_pipeline_result(session: Session, idea_id: UUID) -> PipelineResultRead | None:
    result = session.exec(
        select(PipelineResultModel)
        .where(PipelineResultModel.ideaId == idea_id)
        .order_by(col(PipelineResultModel.createdAt).desc())
        .limit(1)
    ).first()
    if not result:
        return None
    suggestions = session.exec(
        select(PlaceSuggestionModel).where(PlaceSuggestionModel.resultId == result.id)
    ).all()
    read = PipelineResultRead.model_validate(result)
    read.placeSuggestions = []
    for s in suggestions:
        sr = PlaceSuggestionRead.model_validate(s)
        if s.placeId:
            place = session.get(PlaceModel, s.placeId)
            if place:
                sr.placeName = place.name
        read.placeSuggestions.append(sr)
    return read


def _idea_read_with_extras(
    session: Session,
    idea: IdeaModel | IdeaWithPlanCountView,
    plan_count: int | None = None,
) -> IdeaRead:
    read = IdeaRead.model_validate(idea)
    read.planCount = getattr(idea, "planCount", 0) if plan_count is None else plan_count
    read.pipelineResult = _get_latest_pipeline_result(session, idea.id)
    if idea.placeId:
        place = session.get(PlaceModel, idea.placeId)
        if place:
            read.placeName = place.name
    return read


@ideasRouter.get("/ideas", response_model=list[IdeaRead])
def listIdeas(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[IdeaRead]:
    rows = session.exec(
        select(IdeaWithPlanCountView)
        .where(IdeaWithPlanCountView.userId == user.id)
        .order_by(col(IdeaWithPlanCountView.createdAt).desc())
    ).all()

    results: list[IdeaRead] = []
    for row in rows:
        results.append(_idea_read_with_extras(session, row))
    return results


@ideasRouter.post("/ideas", response_model=IdeaRead, status_code=201)
def createIdea(
    body: IdeaCreate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> IdeaRead:
    if not body.title.strip():
        raise BadRequest("Title is required")

    idea = IdeaModel(
        userId=user.id,
        title=body.title.strip(),
        notes=body.notes,
        sourceUrl=body.sourceUrl,
        displayName=body.displayName,
    )
    session.add(idea)
    commitAndRefresh(session, idea)
    return _idea_read_with_extras(session, idea, 0)


@ideasRouter.get("/ideas/{ideaId}", response_model=IdeaRead)
def getIdea(
    ideaId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> IdeaRead:
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")
    view_row = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    return _idea_read_with_extras(session, view_row if view_row else idea)


@ideasRouter.patch("/ideas/{ideaId}", response_model=IdeaRead)
def updateIdea(
    ideaId: UUID,
    body: IdeaUpdate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> IdeaRead:
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")

    update_data = body.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(idea, key, value)
    idea.updatedAt = datetime.utcnow()

    session.add(idea)
    commitAndRefresh(session, idea)
    view_row = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    return _idea_read_with_extras(session, view_row if view_row else idea)


@ideasRouter.delete("/ideas/{ideaId}", status_code=204)
def deleteIdea(
    ideaId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")
    session.delete(idea)
    session.commit()


def _auto_select_place(
    session: Session,
    idea: IdeaModel,
    result: PipelineResultModel,
    suggestions: list[tuple[PlaceSuggestionModel, float | None]],
) -> None:
    """Auto-select when confidence > 0.9 or exactly one suggestion."""
    if len(suggestions) == 1:
        sel, _ = suggestions[0]
        sel.isSelected = True
        idea.placeId = sel.placeId
        session.add(sel)
        return
    for sel, conf in suggestions:
        if conf is not None and conf > 0.9:
            sel.isSelected = True
            idea.placeId = sel.placeId
            session.add(sel)
            for other, _ in suggestions:
                if other.id != sel.id:
                    other.isSelected = False
                    session.add(other)
            return


@ideasRouter.post("/ideas/{ideaId}/interpret", response_model=IdeaRead)
def interpretIdea(
    ideaId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> IdeaRead:
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")

    idea.status = IdeaStatus.suggesting
    idea.updatedAt = datetime.utcnow()
    session.add(idea)
    session.flush()

    result_dict = interpret_with_openai(idea.title)

    pipeline_result = PipelineResultModel(
        ideaId=idea.id,
        jobId=None,
        source="scribble",
        refinedTitle=result_dict.get("refinedTitle"),
        category=result_dict.get("category"),
        estimatedMinutes=result_dict.get("estimatedMinutes"),
        modelName=result_dict.get("modelName"),
        rawOutput=result_dict,
    )
    session.add(pipeline_result)
    session.flush()

    suggestions: list[tuple[PlaceSuggestionModel, float | None]] = []
    search_query = result_dict.get("searchQuery")
    if search_query:
        place_data = search_google_places(search_query)
        if place_data:
            _upsert_place(session, idea, place_data)
            place = session.get(PlaceModel, idea.placeId) if idea.placeId else None
            place_name = place.name if place else place_data.get("name", "")
            sugg = PlaceSuggestionModel(
                resultId=pipeline_result.id,
                placeId=idea.placeId,
                rawName=place_name,
                confidence=1.0,
            )
            session.add(sugg)
            session.flush()
            suggestions.append((sugg, 1.0))

    _auto_select_place(session, idea, pipeline_result, suggestions)

    # specificDatetime from AI stays in rawOutput; surfaced as slot option in PlanOverview
    idea.status = IdeaStatus.ready
    idea.updatedAt = datetime.utcnow()
    session.add(idea)
    commitAndRefresh(session, idea, pipeline_result)

    view_row = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    read = _idea_read_with_extras(session, view_row if view_row else idea)

    invitees = result_dict.get("invitees", [])
    if invitees and read.pipelineResult:
        resolved = _resolve_invitees(session, user.id, invitees)
        read.pipelineResult.rawOutput = {
            **(read.pipelineResult.rawOutput or {}),
            "resolvedInvitees": resolved,
        }

    return read


@ideasRouter.patch("/ideas/{ideaId}/place-suggestions/{suggestionId}", response_model=IdeaRead)
def selectPlaceSuggestion(
    ideaId: UUID,
    suggestionId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> IdeaRead:
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")

    suggestion = session.get(PlaceSuggestionModel, suggestionId)
    if not suggestion:
        raise NotFound("Place suggestion not found")

    result = session.get(PipelineResultModel, suggestion.resultId)
    if not result or result.ideaId != idea.id:
        raise BadRequest("Suggestion does not belong to this idea")

    others = session.exec(
        select(PlaceSuggestionModel).where(PlaceSuggestionModel.resultId == result.id)
    ).all()
    for s in others:
        s.isSelected = s.id == suggestionId
        session.add(s)

    idea.placeId = suggestion.placeId
    idea.updatedAt = datetime.utcnow()
    session.add(idea)
    commitAndRefresh(session, idea)

    view_row = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    return _idea_read_with_extras(session, view_row if view_row else idea)


@ideasRouter.post("/ideas/{ideaId}/suggest-slots")
def suggestSlotsForIdea(
    ideaId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> dict:
    """Generate suggested time slots for an idea (on demand, not stored)."""
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")

    pipeline_result = _get_latest_pipeline_result(session, idea.id)
    preference = "any"
    estimated_minutes = 60
    opening_hours = None

    if pipeline_result:
        raw = pipeline_result.rawOutput or {}
        preference = raw.get("preference") or "any"
        estimated_minutes = pipeline_result.estimatedMinutes or 60

    if idea.placeId:
        place = session.get(PlaceModel, idea.placeId)
        if place and place.openingHours:
            opening_hours = place.openingHours

    slots = suggest_time_slots(
        preference=preference,
        estimated_minutes=estimated_minutes,
        opening_hours=opening_hours,
    )
    return {"slots": slots}


@ideasRouter.post("/ideas/{ideaId}/plan", response_model=PlanRead)
def promoteIdeaToPlan(
    ideaId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> PlanRead:
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")

    pipeline_result = _get_latest_pipeline_result(session, idea.id)
    estimated_minutes = 60
    invitees: list[str] = []
    plan_title = idea.title

    if pipeline_result:
        raw = pipeline_result.rawOutput or {}
        estimated_minutes = pipeline_result.estimatedMinutes or 60
        invitees = raw.get("invitees", [])
        if pipeline_result.refinedTitle:
            plan_title = pipeline_result.refinedTitle

    # Plan always starts as draft with scheduledAt = null. Time is set in PlanOverview.
    share_code = secrets.token_urlsafe(8)

    plan = PlanModel(
        creatorId=user.id,
        placeId=idea.placeId,
        ideaId=idea.id,
        title=plan_title,
        scheduledAt=None,
        status=PlanStatus.draft,
        shareCode=share_code,
        rawPrompt=idea.title,
        estimatedMinutes=estimated_minutes,
    )
    session.add(plan)
    session.flush()

    organizer = PlanMemberModel(
        planId=plan.id,
        userId=user.id,
        role=MemberRole.organizer,
        rsvpStatus=RsvpStatus.accepted,
    )
    session.add(organizer)

    if invitees:
        resolved = _resolve_invitees(session, user.id, invitees)
        for r in resolved:
            if r.get("userId") and str(r["userId"]) != str(user.id):
                member = PlanMemberModel(
                    planId=plan.id,
                    userId=UUID(str(r["userId"])),
                    role=MemberRole.member,
                    rsvpStatus=RsvpStatus.pending,
                    inviteToken=secrets.token_urlsafe(12),
                )
                session.add(member)
                notification = NotificationModel(
                    userId=UUID(str(r["userId"])),
                    type=NotificationType.invite_received,
                    planId=plan.id,
                    title=f"{user.firstName or 'Someone'} invited you to {plan_title}",
                )
                session.add(notification)

    commitAndRefresh(session, plan, idea)

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

    plan_read = PlanRead.model_validate(plan)
    plan_read.members = member_reads
    if idea.placeId:
        place = session.get(PlaceModel, idea.placeId)
        if place:
            plan_read.placeName = place.name
    return plan_read


def _upsert_place(session: Session, idea: IdeaModel, place_data: dict) -> None:
    google_place_id = place_data.get("googlePlaceId")
    if google_place_id:
        existing = session.exec(
            select(PlaceModel).where(PlaceModel.googlePlaceId == google_place_id)
        ).first()
        if existing:
            idea.placeId = existing.id
            return

    place = PlaceModel(
        googlePlaceId=google_place_id,
        name=place_data.get("name", ""),
        address=place_data.get("address"),
        city=place_data.get("city"),
        latitude=place_data.get("latitude"),
        longitude=place_data.get("longitude"),
        category=place_data.get("category"),
    )
    session.add(place)
    session.flush()
    idea.placeId = place.id


def _resolve_invitees(
    session: Session, user_id: UUID, invitee_names: list[str]
) -> list[dict]:
    """Resolve @mention names to user IDs via friendships first, then all users."""
    resolved: list[dict] = []

    friend_ids: set[UUID] = set()
    friendships = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.status == FriendshipStatus.accepted,
            (FriendshipModel.requesterId == user_id)
            | (FriendshipModel.addresseeId == user_id),
        )
    ).all()
    for f in friendships:
        friend_ids.add(f.requesterId if f.addresseeId == user_id else f.addresseeId)

    for name in invitee_names:
        name_lower = name.lower()
        found = None

        if friend_ids:
            friends = session.exec(
                select(UserModel).where(
                    col(UserModel.id).in_(friend_ids),
                    (
                        col(UserModel.firstName).ilike(f"%{name_lower}%")
                        | col(UserModel.lastName).ilike(f"%{name_lower}%")
                    ),
                )
            ).all()
            if friends:
                found = friends[0]

        if not found:
            all_matches = session.exec(
                select(UserModel).where(
                    col(UserModel.firstName).ilike(f"%{name_lower}%")
                    | col(UserModel.lastName).ilike(f"%{name_lower}%")
                ).limit(1)
            ).all()
            if all_matches:
                found = all_matches[0]

        if found:
            resolved.append({
                "userId": str(found.id),
                "firstName": found.firstName,
                "lastName": found.lastName,
                "isFriend": found.id in friend_ids,
            })
        else:
            resolved.append({"name": name, "userId": None, "isFriend": False})

    return resolved
