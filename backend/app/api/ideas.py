import logging
import secrets
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlmodel import Session, select, col

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.enrichments import EnrichmentModel, EnrichmentRead
from app.models.ideas import IdeaCreate, IdeaModel, IdeaRead, IdeaUpdate
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
from app.services.interpret import interpret_with_openai
from app.services.places import search_google_places

logger = logging.getLogger("roam.ideas")
ideasRouter = APIRouter()


@ideasRouter.get("/ideas", response_model=list[IdeaRead])
def listIdeas(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[IdeaRead]:
    rows = session.exec(
        select(IdeaModel)
        .where(IdeaModel.userId == user.id)
        .order_by(col(IdeaModel.createdAt).desc())
    ).all()

    results: list[IdeaRead] = []
    for idea in rows:
        read = IdeaRead.model_validate(idea)
        if idea.enrichmentId:
            enrichment = session.get(EnrichmentModel, idea.enrichmentId)
            if enrichment:
                read.enrichment = EnrichmentRead.model_validate(enrichment)
        if idea.placeId:
            place = session.get(PlaceModel, idea.placeId)
            if place:
                read.placeName = place.name
        results.append(read)
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
        savedLink=body.savedLink,
    )
    session.add(idea)
    commitAndRefresh(session, idea)
    return IdeaRead.model_validate(idea)


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
    return IdeaRead.model_validate(idea)


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

    result = interpret_with_openai(idea.title)

    enrichment = EnrichmentModel(
        refinedTitle=result.get("refinedTitle"),
        category=result.get("category"),
        searchQuery=result.get("searchQuery"),
        tags=result.get("tags", []),
        estimatedMinutes=result.get("estimatedMinutes"),
        preference=result.get("preference"),
        aiEnriched=result.get("aiEnriched", False),
        modelName=result.get("modelName"),
        rawOutput=result,
        confidence={},
    )
    session.add(enrichment)
    session.flush()

    idea.enrichmentId = enrichment.id
    idea.updatedAt = datetime.utcnow()

    search_query = result.get("searchQuery")
    if search_query:
        place_data = search_google_places(search_query)
        if place_data:
            _upsert_place(session, idea, place_data)

    session.add(idea)
    commitAndRefresh(session, idea, enrichment)

    read = IdeaRead.model_validate(idea)
    read.enrichment = EnrichmentRead.model_validate(enrichment)
    if idea.placeId:
        place = session.get(PlaceModel, idea.placeId)
        if place:
            read.placeName = place.name

    invitees = result.get("invitees", [])
    if invitees:
        resolved = _resolve_invitees(session, user.id, invitees)
        read.enrichment.rawOutput = {
            **(read.enrichment.rawOutput or {}),
            "resolvedInvitees": resolved,
        }

    return read


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

    enrichment = None
    specific_datetime = None
    estimated_minutes = 60
    invitees: list[str] = []

    if idea.enrichmentId:
        enrichment = session.get(EnrichmentModel, idea.enrichmentId)
        if enrichment and enrichment.rawOutput:
            specific_datetime = enrichment.rawOutput.get("specificDatetime")
            estimated_minutes = enrichment.estimatedMinutes or 60
            invitees = enrichment.rawOutput.get("invitees", [])

    share_code = secrets.token_urlsafe(8)

    plan = PlanModel(
        creatorId=user.id,
        placeId=idea.placeId,
        ideaId=idea.id,
        enrichmentId=idea.enrichmentId,
        title=enrichment.refinedTitle if enrichment and enrichment.refinedTitle else idea.title,
        scheduledAt=datetime.fromisoformat(specific_datetime) if specific_datetime else None,
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

    commitAndRefresh(session, plan)

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
