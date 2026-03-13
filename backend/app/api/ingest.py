import logging
from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, UploadFile, File, Form
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select, col

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import getSession, handleIntegrityConflict
from app.models.ingestion import IngestionJobModel, IngestionJobRead, JobStatus
from app.models.pipeline import PipelineResultModel, PipelineResultRead, PlaceSuggestionModel, PlaceSuggestionRead
from app.models.places import PlaceModel
from app.models.users import UserModel
from app.services.processing import processIngestionJob

logger = logging.getLogger("roam.ingest")

ingestRouter = APIRouter()

# Upload limits for stability and abuse prevention (tune as needed)
MAX_FRAMES = 10
MAX_UPLOAD_BYTES = 20 * 1024 * 1024  # 20 MB total for thumbnail + all frames


class IngestJobResponse(IngestionJobRead):
    pipelineResult: PipelineResultRead | None = None


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
    try:
        session.commit()
        session.refresh(job)
    except IntegrityError:
        def lookupExisting() -> dict | None:
            existing = session.exec(
                select(IngestionJobModel).where(
                    IngestionJobModel.userId == user.id,
                    IngestionJobModel.reelUrl == reelUrl
                )
            ).first()
            return {"jobId": str(existing.id), "status": existing.status.value} if existing else None

        return handleIntegrityConflict(session, lookupExisting, "Duplicate reel URL")

    metadata = {
        "reelUrl": reelUrl,
        "shareText": shareText,
        "reelTitle": reelTitle,
        "ogDescription": ogDescription,
        "ogKeywords": ogKeywords,
    }

    backgroundTasks.add_task(processIngestionJob, str(job.id), framesData, thumbnailData, metadata)

    logger.info("ingest_job_created", extra={"jobId": str(job.id), "reelUrl": reelUrl})
    return {"jobId": str(job.id), "status": "processing"}


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

    pipeline_result: PipelineResultRead | None = None
    if job.status == JobStatus.done:
        result = session.exec(
            select(PipelineResultModel)
            .where(PipelineResultModel.jobId == jobId)
            .order_by(col(PipelineResultModel.createdAt).desc())
            .limit(1)
        ).first()
        if result:
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
            pipeline_result = read

    jobRead = IngestionJobRead.model_validate(job)
    return IngestJobResponse(**jobRead.model_dump(), pipelineResult=pipeline_result)
