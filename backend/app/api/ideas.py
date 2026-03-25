import base64
import json
import logging
import secrets
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, func, or_
from sqlmodel import Session, select, col

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.idea_categories import normalize_category
from app.common.db import commitAndRefresh, getSession
from app.models.collections import CollectionIdeaModel, CollectionMemberModel, CollectionModel
from app.models.ideas import (
    IdeaCreate,
    IdeaModel,
    IdeaPageRead,
    IdeaRead,
    IdeaSharedCollectionsAttach,
    IdeaUpdate,
    IdeaStatus,
    IdeaWithPlanCountView,
)
from app.services.collectionLinks import linkIdeaToPersonalAndShared
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
from app.services.interpret import get_scribble_prompt_version, interpret_idea
from app.services.places import search_google_places
from app.services.scheduling import suggest_time_slots

logger = logging.getLogger("roam.ideas")
ideasRouter = APIRouter()


def _getLatestPipelineResult(session: Session, ideaId: UUID) -> PipelineResultRead | None:
    result = session.exec(
        select(PipelineResultModel)
        .where(PipelineResultModel.ideaId == ideaId)
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


def _collection_ids_for_idea_visible_to_user(
    session: Session,
    idea_id: UUID,
    viewer_user_id: UUID,
) -> list[UUID]:
    rows = session.exec(
        select(CollectionModel.id)
        .join(CollectionIdeaModel, CollectionIdeaModel.collectionId == CollectionModel.id)
        .join(CollectionMemberModel, CollectionMemberModel.collectionId == CollectionModel.id)
        .where(CollectionIdeaModel.ideaId == idea_id)
        .where(CollectionMemberModel.userId == viewer_user_id)
        .order_by(col(CollectionModel.isPersonalDefault).desc(), CollectionModel.name)
    ).all()
    return list(rows)


def _collection_ids_for_ideas_visible_to_user_batch(
    session: Session,
    idea_ids: list[UUID],
    viewer_user_id: UUID,
) -> dict[UUID, list[UUID]]:
    if not idea_ids:
        return {}
    rows = session.exec(
        select(
            CollectionIdeaModel.ideaId,
            CollectionModel.id,
            CollectionModel.isPersonalDefault,
            CollectionModel.name,
        )
        .join(CollectionModel, CollectionModel.id == CollectionIdeaModel.collectionId)
        .join(CollectionMemberModel, CollectionMemberModel.collectionId == CollectionModel.id)
        .where(CollectionIdeaModel.ideaId.in_(idea_ids))
        .where(CollectionMemberModel.userId == viewer_user_id)
    ).all()
    grouped: dict[UUID, list[tuple[UUID, bool, str]]] = {}
    for idea_id, coll_id, is_personal, name in rows:
        grouped.setdefault(idea_id, []).append((coll_id, is_personal, name or ""))
    out: dict[UUID, list[UUID]] = {iid: [] for iid in idea_ids}
    for idea_id, tuples in grouped.items():
        tuples.sort(key=lambda t: (-int(t[1]), t[2].lower()))
        out[idea_id] = [t[0] for t in tuples]
    return out


def _encode_idea_cursor(created_at: datetime, idea_id: UUID) -> str:
    payload = {"c": created_at.isoformat(), "i": str(idea_id)}
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    b = base64.urlsafe_b64encode(raw).decode("ascii")
    return b.rstrip("=")


def _decode_idea_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        pad = "=" * (-len(cursor) % 4)
        raw = base64.urlsafe_b64decode(cursor + pad)
        obj = json.loads(raw.decode("utf-8"))
        c = datetime.fromisoformat(obj["c"])
        i = UUID(str(obj["i"]))
        return c, i
    except Exception as e:
        raise BadRequest("Invalid cursor") from e


def _ideaReadWithExtrasBatch(
    session: Session,
    rows: list[IdeaWithPlanCountView],
    *,
    viewer_user_id: UUID,
) -> list[IdeaRead]:
    if not rows:
        return []
    idea_ids = [r.id for r in rows]
    coll_map = _collection_ids_for_ideas_visible_to_user_batch(session, idea_ids, viewer_user_id)

    subq = (
        select(
            PipelineResultModel.ideaId.label("iid"),
            func.max(PipelineResultModel.createdAt).label("mx"),
        )
        .where(col(PipelineResultModel.ideaId).in_(idea_ids))
        .group_by(PipelineResultModel.ideaId)
    ).subquery()

    pr_rows = session.exec(
        select(PipelineResultModel).join(
            subq,
            and_(
                PipelineResultModel.ideaId == subq.c.iid,
                PipelineResultModel.createdAt == subq.c.mx,
            ),
        )
    ).all()
    by_idea: dict[UUID, PipelineResultModel] = {}
    for pr in pr_rows:
        if pr.ideaId and pr.ideaId not in by_idea:
            by_idea[pr.ideaId] = pr

    result_ids = [pr.id for pr in by_idea.values()]
    suggestions_by_result: dict[UUID, list[PlaceSuggestionModel]] = {rid: [] for rid in result_ids}
    all_sugs: list[PlaceSuggestionModel] = []
    if result_ids:
        all_sugs = list(
            session.exec(
                select(PlaceSuggestionModel).where(col(PlaceSuggestionModel.resultId).in_(result_ids))
            ).all()
        )
        for s in all_sugs:
            suggestions_by_result.setdefault(s.resultId, []).append(s)

    place_ids: set[UUID] = set()
    for row in rows:
        if row.placeId:
            place_ids.add(row.placeId)
    for s in all_sugs:
        if s.placeId:
            place_ids.add(s.placeId)

    place_map: dict[UUID, PlaceModel] = {}
    if place_ids:
        places = session.exec(select(PlaceModel).where(col(PlaceModel.id).in_(place_ids))).all()
        place_map = {p.id: p for p in places}

    pipeline_read_by_idea: dict[UUID, PipelineResultRead] = {}
    for idea_id, pr in by_idea.items():
        read = PipelineResultRead.model_validate(pr)
        read.placeSuggestions = []
        for s in suggestions_by_result.get(pr.id, []):
            sr = PlaceSuggestionRead.model_validate(s)
            if s.placeId and s.placeId in place_map:
                sr.placeName = place_map[s.placeId].name
            read.placeSuggestions.append(sr)
        pipeline_read_by_idea[idea_id] = read

    out: list[IdeaRead] = []
    for row in rows:
        read = IdeaRead.model_validate(row)
        read.planCount = getattr(row, "planCount", 0)
        read.collectionIds = coll_map.get(row.id, [])
        read.pipelineResult = pipeline_read_by_idea.get(row.id)
        if row.placeId and row.placeId in place_map:
            pl = place_map[row.placeId]
            read.placeName = pl.name
            read.placeLatitude = pl.latitude
            read.placeLongitude = pl.longitude
            read.googlePlaceId = pl.googlePlaceId
        out.append(read)
    return out


def _ideaReadWithExtras(
    session: Session,
    idea: IdeaModel | IdeaWithPlanCountView,
    planCount: int | None = None,
    *,
    viewer_user_id: UUID,
) -> IdeaRead:
    read = IdeaRead.model_validate(idea)
    read.planCount = getattr(idea, "planCount", 0) if planCount is None else planCount
    read.pipelineResult = _getLatestPipelineResult(session, idea.id)
    read.collectionIds = _collection_ids_for_idea_visible_to_user(session, idea.id, viewer_user_id)
    if idea.placeId:
        place = session.get(PlaceModel, idea.placeId)
        if place:
            read.placeName = place.name
            read.placeLatitude = place.latitude
            read.placeLongitude = place.longitude
            read.googlePlaceId = place.googlePlaceId
    return read


@ideasRouter.get("/ideas", response_model=IdeaPageRead)
def listIdeas(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
    limit: int = Query(default=30, ge=1, le=100),
    cursor: str | None = Query(default=None),
    include_total: bool = Query(default=False),
) -> IdeaPageRead:
    q = select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.userId == user.id)
    if cursor:
        c_at, c_id = _decode_idea_cursor(cursor)
        q = q.where(
            or_(
                col(IdeaWithPlanCountView.createdAt) < c_at,
                and_(
                    col(IdeaWithPlanCountView.createdAt) == c_at,
                    col(IdeaWithPlanCountView.id) < c_id,
                ),
            )
        )
    q = q.order_by(
        col(IdeaWithPlanCountView.createdAt).desc(),
        col(IdeaWithPlanCountView.id).desc(),
    ).limit(limit + 1)
    rows = list(session.exec(q).all())
    has_more = len(rows) > limit
    if has_more:
        rows = rows[:limit]
    items = _ideaReadWithExtrasBatch(session, rows, viewer_user_id=user.id)
    total_count: int | None = None
    if include_total:
        total_count = session.exec(
            select(func.count(col(IdeaWithPlanCountView.id))).where(
                IdeaWithPlanCountView.userId == user.id
            )
        ).one()
    next_cur: str | None = None
    if has_more and rows:
        last = rows[-1]
        next_cur = _encode_idea_cursor(last.createdAt, last.id)
    return IdeaPageRead(
        items=items,
        nextCursor=next_cur,
        hasMore=has_more,
        totalCount=total_count,
    )


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
    linkIdeaToPersonalAndShared(
        session,
        ideaId=idea.id,
        ownerUserId=user.id,
        sharedCollectionIds=body.collectionIds,
    )
    session.commit()
    session.refresh(idea)
    return _ideaReadWithExtras(session, idea, 0, viewer_user_id=user.id)


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
    viewRow = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    return _ideaReadWithExtras(session, viewRow if viewRow else idea, viewer_user_id=user.id)


@ideasRouter.post("/ideas/{ideaId}/shared-collections", status_code=204)
def attachIdeaSharedCollections(
    ideaId: UUID,
    body: IdeaSharedCollectionsAttach,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    """Link the idea into extra shared collections. Personal default is always present and is ignored if sent."""
    idea = session.get(IdeaModel, ideaId)
    if not idea:
        raise NotFound("Idea not found")
    if idea.userId != user.id:
        raise Forbidden("Not your idea")
    if not body.sharedCollectionIds:
        return
    linkIdeaToPersonalAndShared(
        session,
        ideaId=idea.id,
        ownerUserId=user.id,
        sharedCollectionIds=body.sharedCollectionIds,
    )
    session.commit()


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

    updateData = body.model_dump(exclude_unset=True)
    if "placeId" in updateData:
        pid = updateData["placeId"]
        if pid is not None and session.get(PlaceModel, pid) is None:
            raise BadRequest("Invalid placeId")
    for key, value in updateData.items():
        setattr(idea, key, value)
    idea.updatedAt = datetime.utcnow()

    session.add(idea)
    commitAndRefresh(session, idea)
    viewRow = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    return _ideaReadWithExtras(session, viewRow if viewRow else idea, viewer_user_id=user.id)


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


def _autoSelectPlace(
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

    resultDict = interpret_idea(idea.title)

    pipelineResult = PipelineResultModel(
        ideaId=idea.id,
        jobId=None,
        source="scribble",
        refinedTitle=resultDict.get("refinedTitle"),
        category=normalize_category(resultDict.get("category")),
        estimatedMinutes=resultDict.get("estimatedMinutes"),
        modelName=resultDict.get("modelName"),
        rawOutput=resultDict,
        promptVersion=get_scribble_prompt_version(),
    )
    session.add(pipelineResult)
    session.flush()

    suggestions: list[tuple[PlaceSuggestionModel, float | None]] = []
    searchQuery = resultDict.get("searchQuery")
    if searchQuery:
        placeData = search_google_places(searchQuery)
        if placeData:
            _upsertPlace(session, idea, placeData)
            place = session.get(PlaceModel, idea.placeId) if idea.placeId else None
            placeName = place.name if place else placeData.get("name", "")
            sugg = PlaceSuggestionModel(
                resultId=pipelineResult.id,
                placeId=idea.placeId,
                rawName=placeName,
                confidence=1.0,
            )
            session.add(sugg)
            session.flush()
            suggestions.append((sugg, 1.0))

    _autoSelectPlace(session, idea, pipelineResult, suggestions)

    # specificDatetime from AI stays in rawOutput; surfaced as slot option in PlanOverview
    idea.status = IdeaStatus.ready
    idea.updatedAt = datetime.utcnow()
    session.add(idea)
    commitAndRefresh(session, idea, pipelineResult)

    viewRow = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    read = _ideaReadWithExtras(session, viewRow if viewRow else idea, viewer_user_id=user.id)

    invitees = resultDict.get("invitees", [])
    if invitees and read.pipelineResult:
        resolved = _resolveInvitees(session, user.id, invitees)
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

    viewRow = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    return _ideaReadWithExtras(session, viewRow if viewRow else idea, viewer_user_id=user.id)


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

    pipelineResult = _getLatestPipelineResult(session, idea.id)
    preference = "any"
    estimatedMinutes = 60
    openingHours = None

    if pipelineResult:
        raw = pipelineResult.rawOutput or {}
        preference = raw.get("preference") or "any"
        estimatedMinutes = pipelineResult.estimatedMinutes or 60

    if idea.placeId:
        place = session.get(PlaceModel, idea.placeId)
        if place and place.openingHours:
            openingHours = place.openingHours

    slots = suggest_time_slots(
        preference=preference,
        estimated_minutes=estimatedMinutes,
        opening_hours=openingHours,
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

    pipelineResult = _getLatestPipelineResult(session, idea.id)
    estimatedMinutes = 60
    invitees: list[str] = []
    planTitle = idea.title

    if pipelineResult:
        raw = pipelineResult.rawOutput or {}
        estimatedMinutes = pipelineResult.estimatedMinutes or 60
        invitees = raw.get("invitees", [])
        if pipelineResult.refinedTitle:
            planTitle = pipelineResult.refinedTitle

    # Plan always starts as draft with scheduledAt = null. Time is set in PlanOverview.
    shareCode = secrets.token_urlsafe(8)

    plan = PlanModel(
        creatorId=user.id,
        placeId=idea.placeId,
        ideaId=idea.id,
        title=planTitle,
        scheduledAt=None,
        status=PlanStatus.draft,
        shareCode=shareCode,
        rawPrompt=idea.title,
        estimatedMinutes=estimatedMinutes,
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
        resolved = _resolveInvitees(session, user.id, invitees)
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
                    title=f"{user.firstName or 'Someone'} invited you to {planTitle}",
                )
                session.add(notification)

    commitAndRefresh(session, plan, idea)

    members = session.exec(
        select(PlanMemberModel).where(PlanMemberModel.planId == plan.id)
    ).all()

    memberReads = []
    for m in members:
        mr = PlanMemberRead.model_validate(m)
        memberUser = session.get(UserModel, m.userId)
        if memberUser:
            mr.firstName = memberUser.firstName
            mr.lastName = memberUser.lastName
        memberReads.append(mr)

    planRead = PlanRead.model_validate(plan)
    planRead.members = memberReads
    if idea.placeId:
        place = session.get(PlaceModel, idea.placeId)
        if place:
            planRead.placeName = place.name
    return planRead


def _upsertPlace(session: Session, idea: IdeaModel, placeData: dict) -> None:
    googlePlaceId = placeData.get("googlePlaceId")
    if googlePlaceId:
        existing = session.exec(
            select(PlaceModel).where(PlaceModel.googlePlaceId == googlePlaceId)
        ).first()
        if existing:
            idea.placeId = existing.id
            return

    raw_cat = placeData.get("category")
    place_category = (
        normalize_category(raw_cat)
        if raw_cat is not None and str(raw_cat).strip()
        else None
    )
    place = PlaceModel(
        googlePlaceId=googlePlaceId,
        name=placeData.get("name", ""),
        address=placeData.get("address"),
        city=placeData.get("city"),
        latitude=placeData.get("latitude"),
        longitude=placeData.get("longitude"),
        category=place_category,
    )
    session.add(place)
    session.flush()
    idea.placeId = place.id


def _resolveInvitees(
    session: Session, userId: UUID, inviteeNames: list[str]
) -> list[dict]:
    """Resolve @mention names to user IDs via friendships first, then all users."""
    resolved: list[dict] = []

    friendIds: set[UUID] = set()
    friendships = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.status == FriendshipStatus.accepted,
            (FriendshipModel.requesterId == userId)
            | (FriendshipModel.addresseeId == userId),
        )
    ).all()
    for f in friendships:
        friendIds.add(f.requesterId if f.addresseeId == userId else f.addresseeId)

    for name in inviteeNames:
        nameLower = name.lower()
        found = None

        if friendIds:
            friends = session.exec(
                select(UserModel).where(
                    col(UserModel.id).in_(friendIds),
                    (
                        col(UserModel.firstName).ilike(f"%{nameLower}%")
                        | col(UserModel.lastName).ilike(f"%{nameLower}%")
                    ),
                )
            ).all()
            if friends:
                found = friends[0]

        if not found:
            allMatches = session.exec(
                select(UserModel).where(
                    col(UserModel.firstName).ilike(f"%{nameLower}%")
                    | col(UserModel.lastName).ilike(f"%{nameLower}%")
                ).limit(1)
            ).all()
            if allMatches:
                found = allMatches[0]

        if found:
            resolved.append({
                "userId": str(found.id),
                "firstName": found.firstName,
                "lastName": found.lastName,
                "isFriend": found.id in friendIds,
            })
        else:
            resolved.append({"name": name, "userId": None, "isFriend": False})

    return resolved
