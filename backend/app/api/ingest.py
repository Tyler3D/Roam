import logging
from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, UploadFile, File, Form
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import getSession, handleIntegrityConflict
from app.models.ingestion import (
    ExtractionModel,
    ExtractionRead,
    IngestionJobModel,
    IngestionJobRead,
    JobStatus,
)
from app.models.users import UserModel
from app.services.processing import processIngestionJob

logger = logging.getLogger("roam.ingest")

ingestRouter = APIRouter()

# Upload limits for stability and abuse prevention (tune as needed)
MAX_FRAMES = 10
MAX_UPLOAD_BYTES = 20 * 1024 * 1024  # 20 MB total for thumbnail + all frames


class IngestJobResponse(IngestionJobRead):
    extractions: list[ExtractionRead] = []


@ingestRouter.post("/ingest", status_code=202)
async def createIngestionJob(
    user: UserModel = Depends(getCurrentUser),
    backgroundTasks: BackgroundTasks,
    reelUrl: str = Form(...),
    shareText: Optional[str] = Form(None),
    lpTitle: Optional[str] = Form(None),
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
        lpTitle=lpTitle,
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
        "lpTitle": lpTitle,
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

    extractions: list[ExtractionRead] = []
    if job.status == JobStatus.done:
        rows = session.exec(select(ExtractionModel).where(ExtractionModel.jobId == jobId)).all()
        extractions = [ExtractionRead.model_validate(r) for r in rows]

    jobRead = IngestionJobRead.model_validate(job)
    return IngestJobResponse(**jobRead.model_dump(), extractions=extractions)
