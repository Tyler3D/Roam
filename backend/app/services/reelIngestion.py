import hashlib
import json
import logging
import os
from datetime import datetime
from pathlib import Path
from uuid import UUID

import httpx
from google import genai
from google.genai import types
from pydantic import BaseModel, Field, ValidationError
from sqlmodel import Session, select

from app.common.config import getGeminiApiKey, getGoogleMapsApiKey
from app.common.idea_categories import normalize_category
from app.common.db import getSession
from app.common.backendErrors import ProviderRateLimitError
from app.services.places import extractCity, resolveGoogleTextSearch
from app.models.ideas import IdeaModel, IdeaStatus
from app.models.ingestion import IngestionJobModel, JobStatus
from app.models.pipeline import PipelineResultModel, PlaceSuggestionModel
from app.models.places import PlaceModel
from app.models.users import UserModel
from app.services.collectionLinks import linkIdeaToPersonalAndShared
from app.models.featureFlags import UserFeatureFlagModel
from app.models.savedReels import ReelIngestCandidateModel, SavedReelModel, SavedReelStatus
from app.services.notifications import (
    acceptedFriendIds,
    checkCoincidenceMatch,
    checkSameReelSaved,
    checkTrendingPlace,
    notifyReelProcessed,
)

logger = logging.getLogger("roam.reel_ingestion")

CONFIDENCE_THRESHOLD = 0.7
MAX_IDEA_NOTES_LEN = 4000


def _loadReelPrompt() -> str:
    path = Path(__file__).resolve().parent.parent / "prompts" / "reel_interpret.md"
    return path.read_text(encoding="utf-8")


REEL_SYSTEM_PROMPT = _loadReelPrompt()


def getReelPromptVersion() -> str:
    h = hashlib.md5(REEL_SYSTEM_PROMPT.encode()).hexdigest()[:8]
    return f"reel-{h}"


class ReelCandidate(BaseModel):
    kind: str = Field(description="location | experience | inspiration")
    title: str
    mapsQuery: str | None = None
    placeAddress: str | None = None
    category: str
    tags: list[str] = Field(default_factory=list)
    confidence: float = Field(ge=0.0, le=1.0)
    evidence: str = ""
    displayDescription: str = ""
    confidenceReason: str | None = None


class ReelInterpretOutput(BaseModel):
    reelSummary: str = ""
    reelKind: str = ""
    primaryActivity: str = ""
    candidates: list[ReelCandidate] = Field(default_factory=list)


def _llmDetectedInLabelFromCandidate(c: ReelCandidate) -> str | None:
    """Stable vague location for UI; prefer LLM placeAddress, else mapsQuery."""
    pa = (c.placeAddress or "").strip()
    if pa:
        return pa[:500]
    mq = (c.mapsQuery or "").strip()
    if mq:
        return mq[:500]
    return None



_LEGACY_CATEGORY_MAP: dict[str, str] = {
    "restaurant": "restaurant",
    "bar": "bar",
    "cafe": "cafe",
    "bakery": "cafe",
    "hike": "outdoors",
    "beach": "outdoors",
    "park": "outdoors",
    "museum": "arts-culture",
    "hotel": "travel",
    "shop": "shopping",
    "nightclub": "nightlife",
    "night_club": "nightlife",
    "activity": "other",
    "other": "other",
    "food-drink": "restaurant",
}


def _mapLegacyCategory(raw: str | None) -> str:
    if not raw:
        return normalize_category(None)
    key = raw.lower().strip()
    mapped = _LEGACY_CATEGORY_MAP.get(key, key)
    return normalize_category(mapped)


def _candidateWithNormalizedCategory(c: ReelCandidate) -> ReelCandidate:
    return c.model_copy(update={"category": normalize_category(c.category)})


def _stripJsonFences(raw: str) -> str:
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines)
    return cleaned


def _tryParseLegacyListJson(text: str) -> ReelInterpretOutput | None:
    """Support old array-of-places API shape stored in rawOutput."""
    cleaned = _stripJsonFences(text)
    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, list):
        return None
    candidates: list[ReelCandidate] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        name = (item.get("placeName") or item.get("title") or "").strip() or "Unknown"
        candidates.append(
            ReelCandidate(
                kind="location",
                title=name,
                mapsQuery=name if name != "Unknown" else None,
                placeAddress=item.get("placeAddress"),
                category=_mapLegacyCategory(item.get("category")),
                tags=[],
                confidence=float(item.get("confidence") or 0.0),
                evidence="Legacy reel JSON array",
                confidenceReason=None,
            )
        )
    return ReelInterpretOutput(
        reelSummary="",
        reelKind="unknown",
        primaryActivity="",
        candidates=candidates,
    )


def _buildGeminiContents(framesData: list[bytes], thumbnailData: bytes | None, metadata: dict) -> list:
    """Build multimodal contents for Gemini: text + images."""
    parts: list = []

    text_parts = []
    if metadata.get("reelTitle"):
        text_parts.append(f"Title: {metadata['reelTitle']}")
    if metadata.get("ogDescription"):
        text_parts.append(f"Description: {metadata['ogDescription']}")
    if metadata.get("ogKeywords"):
        text_parts.append(f"Keywords: {metadata['ogKeywords']}")
    if metadata.get("shareText"):
        text_parts.append(f"Caption/Share text: {metadata['shareText']}")
    if metadata.get("reelUrl"):
        text_parts.append(f"URL: {metadata['reelUrl']}")

    if text_parts:
        parts.append(types.Part.from_text(text="\n".join(text_parts)))

    all_images = []
    if thumbnailData:
        all_images.append(thumbnailData)
    all_images.extend(framesData)

    for img_bytes in all_images:
        parts.append(types.Part.from_bytes(data=img_bytes, mime_type="image/jpeg"))

    if not parts:
        parts.append(types.Part.from_text(text="No metadata or images available."))

    return parts


def _callVisionReel(
    framesData: list[bytes], thumbnailData: bytes | None, metadata: dict
) -> ReelInterpretOutput:
    client = genai.Client(api_key=getGeminiApiKey())
    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    contents = _buildGeminiContents(framesData, thumbnailData, metadata)

    try:
        response = client.models.generate_content(
            model=model,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=REEL_SYSTEM_PROMPT,
                response_mime_type="application/json",
                response_schema=ReelInterpretOutput,
                temperature=0.2,
                max_output_tokens=4096,
            ),
        )
    except Exception as e:
        if getattr(e, "status_code", None) == 429 or "rate" in str(e).lower():
            raise ProviderRateLimitError("Gemini rate limit exceeded; try again later.") from e
        raise

    raw = response.text or "{}"
    cleaned = _stripJsonFences(raw)

    try:
        return ReelInterpretOutput.model_validate_json(cleaned)
    except ValidationError:
        logger.warning("reel_structured_parse_failed_trying_legacy", extra={"raw": raw[:200]})
        legacy = _tryParseLegacyListJson(cleaned)
        if legacy is not None:
            return legacy
        logger.error("reel_parse_failed", extra={"raw": raw[:200]})
        return ReelInterpretOutput(
            reelSummary="",
            reelKind="unknown",
            primaryActivity="",
            candidates=[],
        )


def _refinedTitle(parsed: ReelInterpretOutput, fallback: str, filtered: list[ReelCandidate]) -> str:
    s = (parsed.reelSummary or "").strip()
    if s:
        return s[:500]
    s = (parsed.primaryActivity or "").strip()
    if s:
        return s[:500]
    if filtered:
        t = (filtered[0].title or "").strip()
        if t:
            return t[:500]
    return fallback[:500]


def _pipelineCategory(filtered: list[ReelCandidate]) -> str | None:
    if not filtered:
        return None
    return filtered[0].category


def _shouldResolveMaps(c: ReelCandidate) -> bool:
    if c.kind == "location":
        return bool((c.mapsQuery or c.title or "").strip())
    return bool(c.mapsQuery and c.mapsQuery.strip())


def _resolveGoogleMaps(placeName: str, placeAddress: str | None) -> dict | None:
    """Resolve via shared Google Text Search. ProviderRateLimitError bubbles up."""
    result = resolveGoogleTextSearch(placeName, placeAddress)
    if not result:
        return None
    result["placeAddress"] = result.pop("address", None)
    return result


def _reverseGeocodeLatLng(latitude: float, longitude: float) -> dict | None:
    """Google Geocoding API: return googlePlaceId, placeAddress, latitude, longitude."""
    apiKey = getGoogleMapsApiKey()
    if not apiKey:
        return None
    with httpx.Client(timeout=10) as client:
        resp = client.get(
            "https://maps.googleapis.com/maps/api/geocode/json",
            params={"latlng": f"{latitude},{longitude}", "key": apiKey},
        )
        if resp.status_code == 429:
            raise ProviderRateLimitError("Google Maps rate limit exceeded; try again later.")
        resp.raise_for_status()
        data = resp.json()
    results = data.get("results", [])
    if not results:
        return None
    top = results[0]
    loc = top.get("geometry", {}).get("location", {})
    return {
        "latitude": loc.get("lat"),
        "longitude": loc.get("lng"),
        "googlePlaceId": top.get("place_id"),
        "placeAddress": top.get("formatted_address"),
    }


def resolvePlaceFromUserPick(
    session: Session,
    *,
    name: str | None,
    address: str | None,
    latitude: float | None,
    longitude: float | None,
    maps_query: str | None,
    category: str | None,
) -> PlaceModel | None:
    """Create or reuse a places row from user-confirmed picker data (promote / PATCH).

    Prefers coordinates (reverse geocode → place_id), then text search (maps query / name + address).
    """
    name_t = (name or "").strip()
    addr_t = (address or "").strip()
    mq_t = (maps_query or "").strip()

    def _createFromResolved(
        resolved: dict,
        display_name: str,
        lat_fallback: float | None,
        lng_fallback: float | None,
    ) -> PlaceModel | None:
        gid = resolved.get("googlePlaceId")
        lat_r = resolved.get("latitude")
        lng_r = resolved.get("longitude")
        addr_r = resolved.get("placeAddress") or addr_t or None
        return _createOrGetPlace(
            session,
            place_name=(display_name or "Place")[:500],
            address=addr_r,
            google_place_id=gid,
            category=category,
            latitude=lat_r if lat_r is not None else lat_fallback,
            longitude=lng_r if lng_r is not None else lng_fallback,
            city=resolved.get("city"),
            placeTypes=resolved.get("placeTypes"),
            openingHours=resolved.get("openingHours"),
        )

    if latitude is not None and longitude is not None:
        geo = _reverseGeocodeLatLng(latitude, longitude)
        if geo and geo.get("googlePlaceId"):
            label = name_t or mq_t or (geo.get("placeAddress") or "Place").split(",")[0].strip() or "Place"
            return _createFromResolved(geo, label, latitude, longitude)
        return _createOrGetPlace(
            session,
            place_name=(name_t or mq_t or "Pinned location")[:500],
            address=addr_t or ((geo or {}).get("placeAddress")),
            google_place_id=None,
            category=category,
            latitude=latitude,
            longitude=longitude,
        )

    query_key = mq_t or name_t
    if query_key:
        resolved = _resolveGoogleMaps(query_key, addr_t or None) or {}
        if resolved.get("googlePlaceId") or resolved.get("latitude") is not None:
            return _createFromResolved(resolved, query_key, latitude, longitude)
    if addr_t:
        resolved = _resolveGoogleMaps(addr_t, None) or {}
        if resolved.get("googlePlaceId") or resolved.get("latitude") is not None:
            return _createFromResolved(resolved, addr_t, latitude, longitude)
    return None


def _backfillPlace(
    session: Session,
    place: PlaceModel,
    *,
    city: str | None = None,
    placeTypes: list[str] | None = None,
    openingHours: list | None = None,
) -> None:
    """Fill in null fields on an existing place from richer data."""
    updated = False
    if not place.city and city:
        place.city = city
        updated = True
    if not place.openingHours and openingHours:
        place.openingHours = openingHours
        updated = True
    if not place.placeTypes and placeTypes:
        place.placeTypes = placeTypes
        updated = True
    if updated:
        session.add(place)
        session.flush()


def _createOrGetPlace(
    session: Session,
    place_name: str,
    address: str | None,
    google_place_id: str | None,
    category: str | None,
    latitude: float | None,
    longitude: float | None,
    city: str | None = None,
    placeTypes: list[str] | None = None,
    openingHours: list | None = None,
) -> PlaceModel | None:
    if google_place_id:
        existing = session.exec(
            select(PlaceModel).where(PlaceModel.googlePlaceId == google_place_id)
        ).first()
        if existing:
            _backfillPlace(session, existing, city=city, placeTypes=placeTypes, openingHours=openingHours)
            return existing

    place = PlaceModel(
        googlePlaceId=google_place_id,
        name=place_name or "Unknown",
        address=address,
        city=city or extractCity(google_place_id, address or ""),
        latitude=latitude,
        longitude=longitude,
        category=category,
        placeTypes=placeTypes or [],
        openingHours=openingHours or [],
    )
    session.add(place)
    session.flush()
    return place


def createIdeaPipelineFromCandidate(
    session: Session,
    *,
    job_id: UUID,
    user_id: UUID,
    reel_url: str | None,
    candidate: ReelCandidate,
    raw_output: dict,
    saved_reel_id: UUID | None = None,
    override_place_id: UUID | None = None,
) -> UUID:
    """Create idea + pipeline_result + optional place suggestion; return new idea id.

    When *override_place_id* is provided the place is attached directly and
    Google Maps resolution is skipped (the user already chose a place on the client).
    """
    candidate = _candidateWithNormalizedCategory(candidate)
    estimated_minutes = 90
    prompt_version = getReelPromptVersion()
    model_name = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    idea_title = (candidate.title or "Suggestion")[:500]
    desc = (candidate.displayDescription or "").strip()
    notes = desc or (candidate.evidence or candidate.confidenceReason or "").strip()

    idea = IdeaModel(
        userId=user_id,
        title=idea_title,
        displayName=idea_title,
        notes=notes[:MAX_IDEA_NOTES_LEN],
        sourceUrl=reel_url or "",
        savedReelId=saved_reel_id,
        status=IdeaStatus.suggesting,
    )
    session.add(idea)
    session.flush()

    pr = PipelineResultModel(
        ideaId=idea.id,
        jobId=job_id,
        source="reel",
        refinedTitle=(candidate.title or idea_title)[:500] if candidate.title or idea_title else None,
        category=candidate.category,
        estimatedMinutes=estimated_minutes,
        modelName=model_name,
        promptVersion=prompt_version,
        rawOutput=raw_output,
    )
    session.add(pr)
    session.flush()

    suggestions: list[tuple[PlaceSuggestionModel, float | None]] = []

    if override_place_id:
        # User explicitly selected a place on the client — skip Maps resolution.
        from app.models.places import PlaceModel
        place = session.get(PlaceModel, override_place_id)
        if place:
            sugg = PlaceSuggestionModel(
                resultId=pr.id,
                placeId=place.id,
                rawName=candidate.title or idea_title,
                confidence=1.0,
            )
            session.add(sugg)
            session.flush()
            suggestions.append((sugg, 1.0))
    elif _shouldResolveMaps(candidate):
        query_key = (candidate.mapsQuery or candidate.title or "").strip()
        if query_key:
            resolved = _resolveGoogleMaps(query_key, candidate.placeAddress) or {}
            place = _createOrGetPlace(
                session,
                place_name=candidate.title or query_key,
                address=resolved.get("placeAddress", candidate.placeAddress),
                google_place_id=resolved.get("googlePlaceId"),
                category=resolved.get("category") or candidate.category,
                latitude=resolved.get("latitude"),
                longitude=resolved.get("longitude"),
                city=resolved.get("city"),
                placeTypes=resolved.get("placeTypes"),
                openingHours=resolved.get("openingHours"),
            )
            if place:
                sugg = PlaceSuggestionModel(
                    resultId=pr.id,
                    placeId=place.id,
                    rawName=candidate.title or query_key,
                    confidence=candidate.confidence,
                )
                session.add(sugg)
                session.flush()
                suggestions.append((sugg, candidate.confidence))

    _autoSelectPlace(session, idea, suggestions)
    idea.status = IdeaStatus.ready
    idea.updatedAt = datetime.utcnow()
    session.add(idea)
    return idea.id


def _autoSelectPlace(
    session: Session,
    idea: IdeaModel,
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


def _isAutoPromoteEnabled(session: Session, user_id: UUID) -> bool:
    """Check if auto_promote_single_candidate flag is enabled for the user.

    Returns True (auto-promote) by default — the flag lets users opt *out*.
    """
    row = session.exec(
        select(UserFeatureFlagModel).where(
            UserFeatureFlagModel.user_id == user_id,
            UserFeatureFlagModel.flag_name == "auto_promote_single_candidate",
        )
    ).first()
    if row is None:
        return True  # default: auto-promote enabled
    return row.enabled


def _resolvedPlaceForCandidate(session: Session, c: ReelCandidate) -> UUID | None:
    if not _shouldResolveMaps(c):
        return None
    q = (c.mapsQuery or c.title or "").strip()
    if not q:
        return None
    resolved = _resolveGoogleMaps(q, c.placeAddress) or {}
    place = _createOrGetPlace(
        session,
        place_name=c.title or q,
        address=resolved.get("placeAddress", c.placeAddress),
        google_place_id=resolved.get("googlePlaceId"),
        category=resolved.get("category") or c.category,
        latitude=resolved.get("latitude"),
        longitude=resolved.get("longitude"),
        city=resolved.get("city"),
        placeTypes=resolved.get("placeTypes"),
        openingHours=resolved.get("openingHours"),
    )
    return place.id if place else None


def processIngestionJob(
    jobId: str,
    framesData: list[bytes],
    thumbnailData: bytes | None,
    metadata: dict,
) -> None:
    logger.info("reel_ingestion_start", extra={"jobId": jobId})

    sessionGen = getSession()
    session = next(sessionGen)

    try:
        job = session.get(IngestionJobModel, UUID(jobId))
        if not job:
            logger.error("Job not found", extra={"jobId": jobId})
            return

        saved = session.exec(select(SavedReelModel).where(SavedReelModel.jobId == job.id)).first()
        if not saved:
            logger.error("saved_reel_missing_for_job", extra={"jobId": jobId})
            return

        title = metadata.get("reelTitle") or metadata.get("shareText") or "Untitled reel"

        parsed = _callVisionReel(framesData, thumbnailData, metadata)
        filtered = [c for c in parsed.candidates if c.confidence >= CONFIDENCE_THRESHOLD]
        filtered_ordered = sorted(filtered, key=lambda c: c.confidence, reverse=True)
        reel_url = saved.reelUrl

        saved.updatedAt = datetime.utcnow()
        if (metadata.get("reelTitle") or "").strip():
            saved.title = title[:500]
        session.add(saved)
        session.flush()

        idea_ids: list[UUID] = []

        auto_promote = _isAutoPromoteEnabled(session, job.userId)

        if len(filtered_ordered) == 1 and auto_promote:
            c = _candidateWithNormalizedCategory(filtered_ordered[0])
            raw_output = {
                "candidate": c.model_dump(),
                "fullStructured": parsed.model_dump(),
                "metadata": metadata,
            }
            iid = createIdeaPipelineFromCandidate(
                session,
                job_id=UUID(jobId),
                user_id=job.userId,
                reel_url=reel_url,
                candidate=c,
                raw_output=raw_output,
                saved_reel_id=saved.id,
            )
            linkIdeaToPersonalAndShared(
                session,
                ideaId=iid,
                ownerUserId=job.userId,
                sharedCollectionIds=[],
            )
            idea_ids.append(iid)
            saved.status = SavedReelStatus.promoted
        else:
            if not filtered:
                llm_raw = {
                    "synthetic": True,
                    "structured": parsed.model_dump(),
                    "metadata": metadata,
                    "branch": "no_candidates_above_threshold",
                }
                session.add(
                    ReelIngestCandidateModel(
                        savedReelId=saved.id,
                        sortIndex=0,
                        llmRawOutput=llm_raw,
                        resolvedPlaceId=None,
                    )
                )
            else:
                for idx, c in enumerate(filtered_ordered):
                    c = _candidateWithNormalizedCategory(c)
                    rp = _resolvedPlaceForCandidate(session, c)
                    llm_raw = {
                        "candidate": c.model_dump(),
                        "fullStructured": parsed.model_dump(),
                        "metadata": metadata,
                    }
                    session.add(
                        ReelIngestCandidateModel(
                            savedReelId=saved.id,
                            sortIndex=idx,
                            llmRawOutput=llm_raw,
                            llmDetectedInLabel=_llmDetectedInLabelFromCandidate(c),
                            resolvedPlaceId=rp,
                        )
                    )
            saved.status = SavedReelStatus.needs_review

        saved.updatedAt = datetime.utcnow()
        session.add(saved)

        job.status = JobStatus.done
        job.updatedAt = datetime.utcnow()
        session.add(job)
        session.commit()

        logger.info(
            "reel_ingestion_complete",
            extra={
                "jobId": jobId,
                "ideaIds": [str(i) for i in idea_ids],
                "ideaCount": len(idea_ids),
                "savedReelStatus": saved.status.value,
                "candidateCount": len(parsed.candidates),
                "filteredCount": len(filtered),
            },
        )

        try:
            user = session.get(UserModel, job.userId)
            placeName = None
            firstIdeaId = idea_ids[0] if idea_ids else None
            if firstIdeaId:
                firstIdea = session.get(IdeaModel, firstIdeaId)
                if firstIdea and firstIdea.placeId:
                    place = session.get(PlaceModel, firstIdea.placeId)
                    placeName = place.name if place else None

            notifyReelProcessed(
                session,
                userId=job.userId,
                savedReelId=saved.id,
                status=saved.status.value,
                ideaId=firstIdeaId,
                placeName=placeName,
                candidateCount=len(filtered),
            )

            if user and idea_ids:
                friendIds = acceptedFriendIds(session, user.id)
                for iid in idea_ids:
                    ideaObj = session.get(IdeaModel, iid)
                    if ideaObj:
                        checkCoincidenceMatch(session, idea=ideaObj, user=user, friendIds=friendIds)
                        if ideaObj.placeId:
                            checkTrendingPlace(session, placeId=ideaObj.placeId, triggeringUserId=user.id, friendIds=friendIds)

            if user:
                checkSameReelSaved(session, savedReel=saved, user=user)

            session.commit()
        except Exception:
            logger.exception("notification_dispatch_failed", extra={"jobId": jobId})
    except ProviderRateLimitError as e:
        logger.warning("reel_ingestion_rate_limited", extra={"jobId": jobId, "message": str(e)})
        try:
            job = session.get(IngestionJobModel, UUID(jobId))
            if job:
                job.status = JobStatus.failed
                job.error = str(e)
                job.updatedAt = datetime.utcnow()
                session.add(job)
                sr = session.exec(select(SavedReelModel).where(SavedReelModel.jobId == job.id)).first()
                if sr:
                    sr.status = SavedReelStatus.failed
                    sr.updatedAt = datetime.utcnow()
                    session.add(sr)
                session.commit()
        except Exception:
            logger.exception("failed_to_update_job_status", extra={"jobId": jobId})
    except Exception:
        logger.exception("reel_ingestion_failed", extra={"jobId": jobId})
        try:
            job = session.get(IngestionJobModel, UUID(jobId))
            if job:
                job.status = JobStatus.failed
                job.error = "Processing failed"
                job.updatedAt = datetime.utcnow()
                session.add(job)
                sr = session.exec(select(SavedReelModel).where(SavedReelModel.jobId == job.id)).first()
                if sr:
                    sr.status = SavedReelStatus.failed
                    sr.updatedAt = datetime.utcnow()
                    session.add(sr)
                session.commit()
        except Exception:
            logger.exception("failed_to_update_job_status", extra={"jobId": jobId})
    finally:
        try:
            next(sessionGen, None)
        except StopIteration:
            pass
