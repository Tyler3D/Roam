import logging
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy import and_, exists, func, or_
from sqlmodel import Session, col, select

from app.api.ideas import _ideaReadWithExtras
from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.ideas import IdeaModel, IdeaRead, IdeaStatus, IdeaWithPlanCountView
from app.models.ingestion import IngestionJobModel, JobStatus
from app.models.pipeline import PipelineResultModel
from app.models.places import PlaceModel
from app.models.savedReels import (
    CreateIdeaOnReelBody,
    PromoteReelRequest,
    PromoteReelResponse,
    ReelIngestCandidateRead,
    ReelsSummaryRead,
    SavedReelDetailRead,
    SavedReelIdeaSummary,
    SavedReelListItem,
    SavedReelModel,
    SavedReelStatus,
    ReelIngestCandidateModel,
)
from app.models.users import UserModel
from app.services.gcsReels import signedUrlForObject
from app.services.reelPromote import promoteSavedReel

logger = logging.getLogger("roam.reels")

reelsRouter = APIRouter()


def _thumbUrl(path: str | None) -> str | None:
    return signedUrlForObject(path) if path else None


def _pendingCandidatesExist():
    sub = (
        select(1)
        .select_from(ReelIngestCandidateModel)
        .where(
            ReelIngestCandidateModel.savedReelId == SavedReelModel.id,
            ReelIngestCandidateModel.promotedIdeaId.is_(None),
        )
        .correlate_except(ReelIngestCandidateModel)
    )
    return exists(sub)


@reelsRouter.get("/reels/summary", response_model=ReelsSummaryRead)
def reelsSummary(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> ReelsSummaryRead:
    n = session.exec(
        select(func.count(SavedReelModel.id)).where(
            SavedReelModel.userId == user.id,
            or_(
                SavedReelModel.status == SavedReelStatus.needs_review,
                and_(
                    SavedReelModel.status == SavedReelStatus.promoted,
                    _pendingCandidatesExist(),
                ),
            ),
        )
    ).one()
    return ReelsSummaryRead(needsReviewCount=int(n))


@reelsRouter.get("/reels", response_model=list[SavedReelListItem])
def listReels(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> list[SavedReelListItem]:
    rows = session.exec(
        select(SavedReelModel)
        .where(SavedReelModel.userId == user.id)
        .order_by(col(SavedReelModel.createdAt).desc())
        .offset(offset)
        .limit(limit)
    ).all()
    out: list[SavedReelListItem] = []
    for r in rows:
        out.append(
            SavedReelListItem(
                id=r.id,
                jobId=r.jobId,
                reelUrl=r.reelUrl,
                title=r.title,
                status=r.status,
                thumbnailSignedUrl=_thumbUrl(r.thumbnailObjectPath),
                createdAt=r.createdAt,
                updatedAt=r.updatedAt,
            )
        )
    return out


def _reelIdeaSummariesAndIds(
    session: Session,
    r: SavedReelModel,
    job: IngestionJobModel | None,
) -> tuple[list[SavedReelIdeaSummary], list[UUID]]:
    bySaved = session.exec(
        select(IdeaModel)
        .where(IdeaModel.savedReelId == r.id)
        .order_by(col(IdeaModel.createdAt).desc())
    ).all()

    prIds: list[UUID] = []
    if job and job.status == JobStatus.done:
        prs = session.exec(
            select(PipelineResultModel).where(PipelineResultModel.jobId == r.jobId)
        ).all()
        for pr in prs:
            if pr.ideaId:
                prIds.append(pr.ideaId)

    seen: set[UUID] = set()
    summaries: list[SavedReelIdeaSummary] = []

    def appendIdea(idea: IdeaModel) -> None:
        if idea.id in seen:
            return
        seen.add(idea.id)
        pname = None
        if idea.placeId:
            pl = session.get(PlaceModel, idea.placeId)
            if pl:
                pname = pl.name
        summaries.append(
            SavedReelIdeaSummary(
                id=idea.id,
                title=idea.title,
                status=idea.status,
                placeId=idea.placeId,
                placeName=pname,
            )
        )

    for idea in bySaved:
        appendIdea(idea)

    for pid in prIds:
        if pid in seen:
            continue
        idea = session.get(IdeaModel, pid)
        if idea and idea.userId == r.userId:
            appendIdea(idea)

    ideaIdsOut = [s.id for s in summaries]
    return summaries, ideaIdsOut


@reelsRouter.get("/reels/{reelId}", response_model=SavedReelDetailRead)
def getReel(
    reelId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> SavedReelDetailRead:
    r = session.get(SavedReelModel, reelId)
    if not r:
        raise NotFound("Reel not found")
    if r.userId != user.id:
        raise Forbidden("Not your reel")

    job = session.get(IngestionJobModel, r.jobId)
    jobStatusVal = job.status.value if job else "unknown"
    jobErr = job.error if job else None

    cands = session.exec(
        select(ReelIngestCandidateModel)
        .where(ReelIngestCandidateModel.savedReelId == r.id)
        .order_by(col(ReelIngestCandidateModel.sortIndex).asc())
    ).all()
    candReads: list[ReelIngestCandidateRead] = []
    for c in cands:
        resolvedName = None
        if c.resolvedPlaceId:
            pl = session.get(PlaceModel, c.resolvedPlaceId)
            if pl:
                resolvedName = pl.name
        raw = c.llmRawOutput or {}
        isSynthetic = bool(raw.get("synthetic"))
        if isSynthetic:
            previewTitle = r.title or ""
        else:
            candPayload = raw.get("candidate")
            previewTitle = (candPayload.get("title") if isinstance(candPayload, dict) else None) or ""
        candReads.append(
            ReelIngestCandidateRead(
                id=c.id,
                savedReelId=c.savedReelId,
                sortIndex=c.sortIndex,
                previewTitle=previewTitle,
                isSynthetic=isSynthetic,
                resolvedPlaceId=c.resolvedPlaceId,
                promotedIdeaId=c.promotedIdeaId,
                createdAt=c.createdAt,
                resolvedPlaceName=resolvedName,
            )
        )

    ideaSummaries, ideaIds = _reelIdeaSummariesAndIds(session, r, job)

    return SavedReelDetailRead(
        id=r.id,
        jobId=r.jobId,
        reelUrl=r.reelUrl,
        title=r.title,
        status=r.status,
        thumbnailSignedUrl=_thumbUrl(r.thumbnailObjectPath),
        jobStatus=jobStatusVal,
        jobError=jobErr,
        candidates=candReads,
        ideas=ideaSummaries,
        ideaIds=ideaIds,
        createdAt=r.createdAt,
        updatedAt=r.updatedAt,
    )


@reelsRouter.post(
    "/reels/{reelId}/ideas",
    response_model=IdeaRead,
    status_code=status.HTTP_201_CREATED,
)
def createIdeaOnReel(
    reelId: UUID,
    body: CreateIdeaOnReelBody,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> IdeaRead:
    r = session.get(SavedReelModel, reelId)
    if not r:
        raise NotFound("Reel not found")
    if r.userId != user.id:
        raise Forbidden("Not your reel")
    title = body.title.strip()
    if not title:
        raise BadRequest("Title is required")
    if body.placeId is not None and session.get(PlaceModel, body.placeId) is None:
        raise BadRequest("Invalid placeId")

    st = IdeaStatus.ready if body.placeId is not None else IdeaStatus.captured
    idea = IdeaModel(
        userId=user.id,
        title=title[:500],
        notes=(body.notes or "")[:4000],
        sourceUrl=r.reelUrl or "",
        savedReelId=r.id,
        placeId=body.placeId,
        status=st,
    )
    session.add(idea)
    commitAndRefresh(session, idea)
    viewRow = session.exec(
        select(IdeaWithPlanCountView).where(IdeaWithPlanCountView.id == idea.id)
    ).first()
    return _ideaReadWithExtras(session, viewRow if viewRow else idea, 0)


@reelsRouter.post("/reels/{reelId}/promote", response_model=PromoteReelResponse)
def promoteReel(
    reelId: UUID,
    body: PromoteReelRequest,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> PromoteReelResponse:
    return promoteSavedReel(session, reel_id=reelId, user_id=user.id, body=body)
