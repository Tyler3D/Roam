import logging
from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, Query, UploadFile, status
from sqlalchemy import and_, case, exists, func, or_
from sqlmodel import Session, col, select

from app.api.ideas import _ideaReadWithExtras
from app.api.ingest import MAX_FRAMES, MAX_UPLOAD_BYTES, _initialSavedReelTitle
from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.common.idea_categories import normalize_category
from app.models.ideas import IdeaModel, IdeaRead, IdeaStatus, IdeaWithPlanCountView
from app.models.ingestion import IngestionJobModel, JobStatus
from app.models.pipeline import PipelineResultModel, PlaceSuggestionModel
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
from app.services.gcsReels import signedUrlForObject, uploadReelThumbnail
from app.services.collectionLinks import linkIdeaToPersonalAndShared
from app.services.reelIngestion import processIngestionJob
from app.services.reelPromote import promoteSavedReel

logger = logging.getLogger("roam.reels")

MAX_INGEST_RETRIES_PER_REEL = 5

reelsRouter = APIRouter()


def _candidate_payload_confidence(cand_payload: object) -> float | None:
    if not isinstance(cand_payload, dict):
        return None
    v = cand_payload.get("confidence")
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def _thumbUrl(path: str | None, *, reelId: str | None = None) -> str | None:
    if not path:
        return None
    url = signedUrlForObject(path)
    if url is None:
        logger.debug(
            "reel_thumbnail_signed_url_unavailable reelId=%s objectPath=%s",
            reelId or "",
            path,
        )
    return url


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
    # needs_review + failed first (action / error), then in-flight, then promoted.
    # Within each tier: updatedAt desc ≈ when classification last finished (ingest, fail, or promote).
    sortPriority = case(
        (col(SavedReelModel.status) == SavedReelStatus.needs_review, 0),
        (col(SavedReelModel.status) == SavedReelStatus.failed, 0),
        (col(SavedReelModel.status) == SavedReelStatus.processing, 1),
        (col(SavedReelModel.status) == SavedReelStatus.promoted, 2),
        else_=3,
    )
    rows = session.exec(
        select(SavedReelModel)
        .where(SavedReelModel.userId == user.id)
        .order_by(
            sortPriority.asc(),
            col(SavedReelModel.updatedAt).desc(),
            col(SavedReelModel.createdAt).desc(),
        )
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
                thumbnailSignedUrl=_thumbUrl(r.thumbnailObjectPath, reelId=str(r.id)),
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
            preview_desc = ""
            category = ""
            place_addr = None
            maps_q = None
            conf = None
        else:
            candPayload = raw.get("candidate")
            previewTitle = (candPayload.get("title") if isinstance(candPayload, dict) else None) or ""
            preview_desc = (
                (candPayload.get("displayDescription") or candPayload.get("display_description") or "")
                if isinstance(candPayload, dict)
                else ""
            ) or ""
            raw_cat = (
                (candPayload.get("category") or "")
                if isinstance(candPayload, dict)
                else ""
            ) or ""
            category = normalize_category(raw_cat) if raw_cat.strip() else ""
            place_addr = (
                candPayload.get("placeAddress") if isinstance(candPayload, dict) else None
            )
            maps_q = candPayload.get("mapsQuery") if isinstance(candPayload, dict) else None
            conf = _candidate_payload_confidence(candPayload)
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
                previewDescription=preview_desc[:2000] if preview_desc else "",
                category=(category or "")[:200],
                placeAddress=place_addr,
                mapsQuery=maps_q,
                confidence=conf,
            )
        )

    ideaSummaries, ideaIds = _reelIdeaSummariesAndIds(session, r, job)

    return SavedReelDetailRead(
        id=r.id,
        jobId=r.jobId,
        reelUrl=r.reelUrl,
        title=r.title,
        status=r.status,
        thumbnailSignedUrl=_thumbUrl(r.thumbnailObjectPath, reelId=str(r.id)),
        ingestRetryCount=r.ingestRetryCount,
        jobStatus=jobStatusVal,
        jobError=jobErr,
        candidates=candReads,
        ideas=ideaSummaries,
        ideaIds=ideaIds,
        createdAt=r.createdAt,
        updatedAt=r.updatedAt,
    )


@reelsRouter.post("/reels/{reelId}/retry-ingest", status_code=status.HTTP_202_ACCEPTED)
async def retryReelIngest(
    background_tasks: BackgroundTasks,
    reelId: UUID,
    user: UserModel = Depends(getCurrentUser),
    shareText: Optional[str] = Form(None),
    reelTitle: Optional[str] = Form(None),
    ogDescription: Optional[str] = Form(None),
    ogKeywords: Optional[str] = Form(None),
    thumbnail: Optional[UploadFile] = File(None),
    frames: list[UploadFile] = File(default=[]),
    session: Session = Depends(getSession),
) -> dict:
    """Re-run vision ingest for a reel whose job ended in `failed` (e.g. \"Processing failed\")."""
    if len(frames) > MAX_FRAMES:
        raise BadRequest(f"Too many frames; maximum is {MAX_FRAMES}")

    r = session.get(SavedReelModel, reelId)
    if not r:
        raise NotFound("Reel not found")
    if r.userId != user.id:
        raise Forbidden("Not your reel")
    if r.status != SavedReelStatus.failed:
        raise BadRequest("Retry is only available when reel processing has failed")

    job = session.get(IngestionJobModel, r.jobId)
    if not job:
        raise NotFound("Ingest job not found for this reel")
    if job.status != JobStatus.failed:
        raise BadRequest("Only a failed ingest job can be retried")
    if r.ingestRetryCount >= MAX_INGEST_RETRIES_PER_REEL:
        raise BadRequest(f"Maximum of {MAX_INGEST_RETRIES_PER_REEL} retries reached for this reel")

    frames_data: list[bytes] = []
    thumbnail_data: bytes | None = None
    if thumbnail:
        thumbnail_data = await thumbnail.read()
    for frame in frames:
        frames_data.append(await frame.read())

    total_bytes = (len(thumbnail_data) if thumbnail_data else 0) + sum(len(b) for b in frames_data)
    if total_bytes > MAX_UPLOAD_BYTES:
        raise BadRequest(
            f"Upload too large ({(total_bytes / (1024 * 1024)):.1f} MB); maximum is {MAX_UPLOAD_BYTES // (1024 * 1024)} MB"
        )

    for pr in session.exec(select(PipelineResultModel).where(PipelineResultModel.jobId == job.id)).all():
        if pr.ideaId is not None:
            continue
        for sug in session.exec(
            select(PlaceSuggestionModel).where(PlaceSuggestionModel.resultId == pr.id)
        ).all():
            session.delete(sug)
        session.delete(pr)

    for c in session.exec(
        select(ReelIngestCandidateModel).where(ReelIngestCandidateModel.savedReelId == r.id)
    ).all():
        session.delete(c)

    if shareText is not None and shareText.strip():
        job.shareText = shareText
    if reelTitle is not None and reelTitle.strip():
        job.reelTitle = reelTitle.strip()[:500]
        r.title = _initialSavedReelTitle(reelTitle, job.shareText, r.reelUrl)
    if ogDescription is not None:
        job.ogDescription = ogDescription
    if ogKeywords is not None:
        job.ogKeywords = ogKeywords
    job.status = JobStatus.processing
    job.error = None
    job.updatedAt = datetime.utcnow()
    session.add(job)

    r.status = SavedReelStatus.processing
    r.updatedAt = datetime.utcnow()
    r.ingestRetryCount += 1
    session.add(r)

    if thumbnail_data:
        thumb_path = uploadReelThumbnail(user_id=user.id, job_id=job.id, data=thumbnail_data)
        if thumb_path:
            r.thumbnailObjectPath = thumb_path
            session.add(r)

    session.commit()
    session.refresh(job)
    session.refresh(r)

    metadata = {
        "reelUrl": r.reelUrl,
        "shareText": job.shareText,
        "reelTitle": job.reelTitle,
        "ogDescription": job.ogDescription,
        "ogKeywords": job.ogKeywords,
    }
    background_tasks.add_task(processIngestionJob, str(job.id), frames_data, thumbnail_data, metadata)

    logger.info(
        "reel_retry_ingest_scheduled reelId=%s jobId=%s userId=%s",
        reelId,
        job.id,
        user.id,
    )
    return {"jobId": str(job.id), "status": "processing", "reelId": str(r.id)}


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
    linkIdeaToPersonalAndShared(
        session,
        ideaId=idea.id,
        ownerUserId=user.id,
        sharedCollectionIds=body.collectionIds,
    )
    session.commit()
    session.refresh(idea)
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
    """Promote candidates to ideas. Each idea is always linked to the user's personal default collection."""
    return promoteSavedReel(session, reel_id=reelId, user_id=user.id, body=body)


@reelsRouter.delete("/reels/{reelId}", status_code=status.HTTP_204_NO_CONTENT)
def deleteSavedReel(
    reelId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    """Remove this reel from history only: ideas stay; `ideas.savedReelId` is cleared."""
    r = session.get(SavedReelModel, reelId)
    if not r:
        raise NotFound("Reel not found")
    if r.userId != user.id:
        raise Forbidden("Not your reel")

    for idea in session.exec(select(IdeaModel).where(IdeaModel.savedReelId == reelId)).all():
        if idea.userId != user.id:
            continue
        idea.savedReelId = None
        session.add(idea)

    for c in session.exec(
        select(ReelIngestCandidateModel).where(ReelIngestCandidateModel.savedReelId == reelId)
    ).all():
        session.delete(c)

    session.delete(r)
    session.commit()
