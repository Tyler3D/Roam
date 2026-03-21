"""Promote staged reel candidates into ideas (user-initiated)."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlmodel import Session

from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.idea_categories import normalize_category
from app.models.savedReels import (
    PromoteReelRequest,
    PromoteReelResponse,
    ReelIngestCandidateModel,
    SavedReelModel,
    SavedReelStatus,
)
from app.services.collectionLinks import linkIdeaToPersonalAndShared
from app.services.reelIngestion import (
    ReelCandidate,
    ReelInterpretOutput,
    createIdeaPipelineFromCandidate,
    _refinedTitle,
)


def promoteSavedReel(
    session: Session,
    *,
    reel_id: UUID,
    user_id: UUID,
    body: PromoteReelRequest,
) -> PromoteReelResponse:
    saved = session.get(SavedReelModel, reel_id)
    if not saved:
        raise NotFound("Reel not found")
    if saved.userId != user_id:
        raise Forbidden("Not your reel")
    if saved.status not in (SavedReelStatus.needs_review, SavedReelStatus.promoted):
        raise BadRequest("Reel cannot be promoted in its current state")

    if not body.promotions:
        raise BadRequest("promotions must not be empty")

    idea_ids: list[UUID] = []

    for item in body.promotions:
        cand = session.get(ReelIngestCandidateModel, item.candidateId)
        if not cand or cand.savedReelId != saved.id:
            raise BadRequest("Invalid candidateId for this reel")
        if cand.promotedIdeaId:
            continue

        raw = dict(cand.llmRawOutput or {})
        meta = raw.get("metadata") or {}
        reel_url = meta.get("reelUrl")

        if raw.get("synthetic"):
            structured = raw.get("structured") or {}
            try:
                parsed = ReelInterpretOutput.model_validate(structured)
            except Exception:
                parsed = ReelInterpretOutput()
            hint = meta.get("reelTitle") or meta.get("shareText") or saved.title or "Saved reel"
            ref = _refinedTitle(parsed, hint, [])
            title = (item.title or ref or hint)[:500]
            rc = ReelCandidate(
                kind="experience",
                title=title,
                mapsQuery=item.mapsQuery,
                placeAddress=item.placeAddress,
                category=normalize_category(item.category or "other")[:200],
                tags=[],
                confidence=0.5,
                evidence="",
            )
            raw_out = {**raw, "promotedFromSynthetic": True}
        else:
            raw_c = raw.get("candidate") or {}
            try:
                rc = ReelCandidate.model_validate(raw_c)
            except Exception:
                raise BadRequest("Invalid llmRawOutput candidate") from None
            if item.title:
                rc = rc.model_copy(update={"title": item.title})
            if item.mapsQuery is not None:
                rc = rc.model_copy(update={"mapsQuery": item.mapsQuery})
            if item.placeAddress is not None:
                rc = rc.model_copy(update={"placeAddress": item.placeAddress})
            if item.category is not None:
                rc = rc.model_copy(update={"category": normalize_category(item.category)})
            raw_out = {
                "candidate": rc.model_dump(),
                "fullStructured": raw.get("fullStructured"),
                "metadata": meta,
                "promotedFromStaged": True,
            }

        iid = createIdeaPipelineFromCandidate(
            session,
            job_id=saved.jobId,
            user_id=user_id,
            reel_url=reel_url,
            candidate=rc,
            raw_output=raw_out,
            saved_reel_id=saved.id,
        )
        cand.promotedIdeaId = iid
        session.add(cand)
        idea_ids.append(iid)
        linkIdeaToPersonalAndShared(
            session,
            ideaId=iid,
            ownerUserId=user_id,
            sharedCollectionIds=body.collectionIds,
        )

    if not idea_ids:
        raise BadRequest("No candidates could be promoted")

    saved.status = SavedReelStatus.promoted
    saved.updatedAt = datetime.utcnow()
    session.add(saved)
    session.commit()

    return PromoteReelResponse(ideaIds=idea_ids, reelStatus=saved.status)
