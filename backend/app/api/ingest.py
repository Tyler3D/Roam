import logging
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, UploadFile, File, Form
from fastapi.responses import JSONResponse
from pydantic import Field
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select, col

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import getSession, handleIntegrityConflict
from app.models.ingestion import IngestionJobModel, IngestionJobRead, JobStatus
from app.models.pipeline import PipelineResultModel, PipelineResultRead, PlaceSuggestionModel, PlaceSuggestionRead
from app.models.places import PlaceModel
from app.models.savedReels import SavedReelModel, SavedReelStatus
from app.models.users import UserModel
from app.services.gcsReels import uploadReelThumbnail
from app.services.reelIngestion import processIngestionJob

logger = logging.getLogger("roam.ingest")

ingestRouter = APIRouter()

# Upload limits for stability and abuse prevention (tune as needed)
MAX_FRAMES = 10
MAX_UPLOAD_BYTES = 20 * 1024 * 1024  # 20 MB total for thumbnail + all frames


def _initialSavedReelTitle(
    reelTitle: Optional[str], shareText: Optional[str], reelUrl: str
) -> str:
    t = (reelTitle or "").strip()
    if t:
        return t[:500]
    st = (shareText or "").strip()
    if st:
        line = st.split("\n")[0].strip()
        return (line[:500] if line else "Shared reel")
    return (reelUrl[:200] if reelUrl else "Reel")[:500]


def _pipelineResultToRead(session: Session, result: PipelineResultModel) -> PipelineResultRead:
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


class IngestJobResponse(IngestionJobRead):
    """GET /ingest/{jobId}: one reel job can produce multiple ideas (one pipeline_result per candidate)."""

    pipelineResult: PipelineResultRead | None = None
    pipelineResults: list[PipelineResultRead] = Field(default_factory=list)


@ingestRouter.post("/ingest", status_code=202)
async def createIngestionJob(
    backgroundTasks: BackgroundTasks,
    user: UserModel = Depends(getCurrentUser),
    reelUrl: str = Form(...),
    shareText: Optional[str] = Form(None),
    reelTitle: Optional[str] = Form(None),
    ogDescription: Optional[str] = Form(None),
    ogKeywords: Optional[str] = Form(None),
    thumbnail: Optional[UploadFile] = File(None),
    frames: list[UploadFile] = File(default=[]),
    session: Session = Depends(getSession),
) -> dict:
    if len(frames) > MAX_FRAMES:
        raise BadRequest(f"Too many frames; maximum is {MAX_FRAMES}")

    framesData: list[bytes] = []
    thumbnailData: bytes | None = None

    if thumbnail:
        thumbnailData = await thumbnail.read()
    for frame in frames:
        framesData.append(await frame.read())

    totalBytes = (len(thumbnailData) if thumbnailData else 0) + sum(len(b) for b in framesData)
    if totalBytes > MAX_UPLOAD_BYTES:
        raise BadRequest(
            f"Upload too large ({(totalBytes / (1024 * 1024)):.1f} MB); maximum is {MAX_UPLOAD_BYTES // (1024 * 1024)} MB"
        )

    job = IngestionJobModel(
        userId=user.id,
        reelUrl=reelUrl,
        shareText=shareText,
        reelTitle=reelTitle,
        ogDescription=ogDescription,
        ogKeywords=ogKeywords,
        status=JobStatus.processing,
    )
    session.add(job)
    session.flush()

    thumbPath = None
    if thumbnailData:
        thumbPath = uploadReelThumbnail(user_id=user.id, job_id=job.id, data=thumbnailData)

    savedReel = SavedReelModel(
        userId=user.id,
        jobId=job.id,
        reelUrl=reelUrl,
        title=_initialSavedReelTitle(reelTitle, shareText, reelUrl),
        thumbnailObjectPath=thumbPath,
        status=SavedReelStatus.processing,
    )
    session.add(savedReel)

    try:
        session.commit()
        session.refresh(job)
        session.refresh(savedReel)
    except IntegrityError:
        def lookupExisting() -> dict | None:
            existing = session.exec(
                select(IngestionJobModel).where(
                    IngestionJobModel.userId == user.id,
                    IngestionJobModel.reelUrl == reelUrl,
                )
            ).first()
            if not existing:
                return None
            payload: dict = {"jobId": str(existing.id), "status": existing.status.value}
            sr = session.exec(select(SavedReelModel).where(SavedReelModel.jobId == existing.id)).first()
            if sr:
                payload["reelId"] = str(sr.id)
            if existing.status == JobStatus.done:
                prs = session.exec(
                    select(PipelineResultModel)
                    .where(PipelineResultModel.jobId == existing.id)
                    .order_by(col(PipelineResultModel.createdAt).asc())
                ).all()
                ideaIds = [str(p.ideaId) for p in prs if p.ideaId]
                if ideaIds:
                    payload["ideaIds"] = ideaIds
                    payload["ideaId"] = ideaIds[0]
            return payload

        payload = handleIntegrityConflict(session, lookupExisting, "Duplicate reel URL")
        return JSONResponse(status_code=202, content=payload)

    metadata = {
        "reelUrl": reelUrl,
        "shareText": shareText,
        "reelTitle": reelTitle,
        "ogDescription": ogDescription,
        "ogKeywords": ogKeywords,
    }

    backgroundTasks.add_task(processIngestionJob, str(job.id), framesData, thumbnailData, metadata)

    logger.info(
        "ingest_job_created",
        extra={"jobId": str(job.id), "reelUrl": reelUrl, "reelId": str(savedReel.id)},
    )
    return {"jobId": str(job.id), "status": "processing", "reelId": str(savedReel.id)}


@ingestRouter.get("/ingest/{jobId}", response_model=IngestJobResponse)
def getIngestionJob(
    jobId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> IngestJobResponse:

    job = session.get(IngestionJobModel, jobId)
    if not job:
        raise NotFound("Job not found")
    if job.userId != user.id:
        raise Forbidden("Not your job")

    pipelineReads: list[PipelineResultRead] = []
    if job.status == JobStatus.done:
        results = session.exec(
            select(PipelineResultModel)
            .where(PipelineResultModel.jobId == jobId)
            .order_by(col(PipelineResultModel.createdAt).asc())
        ).all()
        for result in results:
            pipelineReads.append(_pipelineResultToRead(session, result))

    jobRead = IngestionJobRead.model_validate(job)
    first = pipelineReads[0] if pipelineReads else None
    return IngestJobResponse(
        **jobRead.model_dump(),
        pipelineResult=first,
        pipelineResults=pipelineReads,
    )
