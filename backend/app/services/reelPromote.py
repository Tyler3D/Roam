"""Promote staged reel candidates into ideas (user-initiated)."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlmodel import Session, select

from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.idea_categories import normalize_category
from app.models.places import PlaceModel
from app.models.savedReels import (
    PromoteReelRequest,
    PromoteReelResponse,
    ReelCandidateUserPlaceModel,
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

        existing_up = session.exec(
            select(ReelCandidateUserPlaceModel).where(
                ReelCandidateUserPlaceModel.candidate_id == cand.id,
                ReelCandidateUserPlaceModel.user_id == user_id,
            )
        ).first()
        patch_snapshot = (
            (
                existing_up.place_name,
                existing_up.place_address,
                existing_up.latitude,
                existing_up.longitude,
                existing_up.maps_query,
            )
            if existing_up
            else None
        )

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
            syn_mq = item.mapsQuery
            syn_pa = item.placeAddress
            if existing_up:
                if not (syn_mq or "").strip() and (existing_up.maps_query or "").strip():
                    syn_mq = existing_up.maps_query
                elif not (syn_mq or "").strip() and (existing_up.place_name or "").strip():
                    syn_mq = existing_up.place_name
                if not (syn_pa or "").strip() and (existing_up.place_address or "").strip():
                    syn_pa = existing_up.place_address
            rc = ReelCandidate(
                kind="experience",
                title=title,
                mapsQuery=syn_mq,
                placeAddress=syn_pa,
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
            # Promote body may omit fields; reuse PATCH /place row so Maps resolves the user's pick, not the stale LLM row.
            if existing_up:
                mq = (rc.mapsQuery or "").strip()
                pa = (rc.placeAddress or "").strip()
                umq = (existing_up.maps_query or "").strip()
                uaddr = (existing_up.place_address or "").strip()
                uname = (existing_up.place_name or "").strip()
                if not mq and umq:
                    rc = rc.model_copy(update={"mapsQuery": existing_up.maps_query})
                elif not mq and uname:
                    rc = rc.model_copy(update={"mapsQuery": existing_up.place_name})
                if not pa and uaddr:
                    rc = rc.model_copy(update={"placeAddress": existing_up.place_address})
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
            override_place_id=item.placeId,
        )
        cand.promotedIdeaId = iid
        session.add(cand)
        idea_ids.append(iid)

        # Record user-confirmed place in the join table (upsert).
        from app.models.ideas import IdeaModel
        idea = session.get(IdeaModel, iid)
        place = session.get(PlaceModel, idea.placeId) if idea and idea.placeId else None
        if existing_up:
            existing_up.place_id = idea.placeId if idea else None
            pn, pa, plat, plng, pmq = patch_snapshot  # set together with existing_up above
            has_user_patch = (
                plat is not None
                or plng is not None
                or (pa or "").strip()
                or (pmq or "").strip()
                or (pn or "").strip()
            )
            if has_user_patch:
                existing_up.place_name = pn
                existing_up.place_address = pa
                existing_up.latitude = plat
                existing_up.longitude = plng
                existing_up.maps_query = pmq
            else:
                existing_up.place_name = place.name if place else (rc.title or None)
                existing_up.place_address = place.address if place else (rc.placeAddress or None)
                existing_up.latitude = place.latitude if place else None
                existing_up.longitude = place.longitude if place else None
                existing_up.maps_query = rc.mapsQuery
            existing_up.source = "user"
            existing_up.confirmed_at = datetime.utcnow()
            session.add(existing_up)
        else:
            user_place = ReelCandidateUserPlaceModel(
                candidate_id=cand.id,
                user_id=user_id,
                place_id=idea.placeId if idea else None,
                place_name=place.name if place else (rc.title or None),
                place_address=place.address if place else (rc.placeAddress or None),
                latitude=place.latitude if place else None,
                longitude=place.longitude if place else None,
                maps_query=rc.mapsQuery,
                source="user",
            )
            session.add(user_place)

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
