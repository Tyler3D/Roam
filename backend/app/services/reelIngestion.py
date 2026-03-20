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
from app.common.db import getSession
from app.models.ideas import IdeaModel, IdeaStatus
from app.models.ingestion import IngestionJobModel, JobStatus
from app.models.pipeline import PipelineResultModel, PlaceSuggestionModel
from app.models.places import PlaceModel

logger = logging.getLogger("roam.reel_ingestion")

CONFIDENCE_THRESHOLD = 0.7


def _load_reel_prompt() -> str:
    path = Path(__file__).resolve().parent.parent / "prompts" / "reel_interpret.md"
    return path.read_text(encoding="utf-8")


REEL_SYSTEM_PROMPT = _load_reel_prompt()


def get_reel_prompt_version() -> str:
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
    confidenceReason: str | None = None


class ReelInterpretOutput(BaseModel):
    reelSummary: str = ""
    reelKind: str = ""
    primaryActivity: str = ""
    candidates: list[ReelCandidate] = Field(default_factory=list)


class ProviderRateLimitError(Exception):
    """OpenAI or Google Maps returned 429 / rate limit; job should fail with clear message."""


_LEGACY_CATEGORY_MAP: dict[str, str] = {
    "restaurant": "food-drink",
    "bar": "nightlife",
    "cafe": "food-drink",
    "hike": "outdoors",
    "beach": "outdoors",
    "park": "outdoors",
    "museum": "arts-culture",
    "hotel": "travel",
    "shop": "shopping",
    "nightclub": "nightlife",
    "activity": "other",
    "other": "other",
}


def _map_legacy_category(raw: str | None) -> str:
    if not raw:
        return "other"
    key = raw.lower().strip()
    return _LEGACY_CATEGORY_MAP.get(key, "other")


def _strip_json_fences(raw: str) -> str:
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines)
    return cleaned


def _try_parse_legacy_list_json(text: str) -> ReelInterpretOutput | None:
    """Support old array-of-places API shape stored in rawOutput."""
    cleaned = _strip_json_fences(text)
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
                category=_map_legacy_category(item.get("category")),
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


def _build_gemini_contents(framesData: list[bytes], thumbnailData: bytes | None, metadata: dict) -> list:
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


def _call_vision_reel(
    framesData: list[bytes], thumbnailData: bytes | None, metadata: dict
) -> ReelInterpretOutput:
    client = genai.Client(api_key=getGeminiApiKey())
    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    contents = _build_gemini_contents(framesData, thumbnailData, metadata)

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
    cleaned = _strip_json_fences(raw)

    try:
        return ReelInterpretOutput.model_validate_json(cleaned)
    except ValidationError:
        logger.warning("reel_structured_parse_failed_trying_legacy", extra={"raw": raw[:200]})
        legacy = _try_parse_legacy_list_json(cleaned)
        if legacy is not None:
            return legacy
        logger.error("reel_parse_failed", extra={"raw": raw[:200]})
        return ReelInterpretOutput(
            reelSummary="",
            reelKind="unknown",
            primaryActivity="",
            candidates=[],
        )


def _refined_title(parsed: ReelInterpretOutput, fallback: str, filtered: list[ReelCandidate]) -> str:
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


def _pipeline_category(filtered: list[ReelCandidate]) -> str | None:
    if not filtered:
        return None
    return filtered[0].category


def _should_resolve_maps(c: ReelCandidate) -> bool:
    if c.kind == "location":
        return bool((c.mapsQuery or c.title or "").strip())
    return bool(c.mapsQuery and c.mapsQuery.strip())


def _resolveGoogleMaps(placeName: str, placeAddress: str | None) -> dict | None:
    apiKey = getGoogleMapsApiKey()
    if not apiKey:
        return None

    query = placeName
    if placeAddress:
        query = f"{placeName} {placeAddress}"

    try:
        with httpx.Client(timeout=10) as client:
            resp = client.get(
                "https://maps.googleapis.com/maps/api/place/textsearch/json",
                params={"query": query, "key": apiKey},
            )
            if resp.status_code == 429:
                raise ProviderRateLimitError("Google Maps rate limit exceeded; try again later.")
            resp.raise_for_status()
            data = resp.json()

        results = data.get("results", [])
        if not results:
            return None

        top = results[0]
        location = top.get("geometry", {}).get("location", {})
        return {
            "latitude": location.get("lat"),
            "longitude": location.get("lng"),
            "googlePlaceId": top.get("place_id"),
            "placeAddress": top.get("formatted_address"),
        }
    except ProviderRateLimitError:
        raise
    except Exception:
        logger.exception("Google Maps API call failed", extra={"query": query})
        return None


def _create_or_get_place(
    session: Session,
    place_name: str,
    address: str | None,
    google_place_id: str | None,
    category: str | None,
    latitude: float | None,
    longitude: float | None,
) -> PlaceModel | None:
    if google_place_id:
        existing = session.exec(
            select(PlaceModel).where(PlaceModel.googlePlaceId == google_place_id)
        ).first()
        if existing:
            return existing

    place = PlaceModel(
        googlePlaceId=google_place_id,
        name=place_name or "Unknown",
        address=address,
        city=None,
        latitude=latitude,
        longitude=longitude,
        category=category,
    )
    session.add(place)
    session.flush()
    return place


def _auto_select_place(
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

        title = metadata.get("reelTitle") or metadata.get("shareText") or "Untitled reel"

        if job.ideaId:
            idea = session.get(IdeaModel, job.ideaId)
            if not idea or idea.userId != job.userId:
                logger.error(
                    "reel_ingestion_missing_idea",
                    extra={"jobId": jobId, "ideaId": str(job.ideaId) if job.ideaId else None},
                )
                return
            if (metadata.get("reelTitle") or "").strip():
                idea.title = title[:500]
            url = metadata.get("reelUrl")
            if url:
                idea.sourceUrl = url
            idea.status = IdeaStatus.suggesting
            idea.updatedAt = datetime.utcnow()
            session.add(idea)
            session.flush()
        else:
            idea = IdeaModel(
                userId=job.userId,
                title=title[:500],
                sourceUrl=metadata.get("reelUrl"),
                status=IdeaStatus.captured,
            )
            session.add(idea)
            session.flush()

            idea.status = IdeaStatus.suggesting
            idea.updatedAt = datetime.utcnow()
            session.add(idea)
            session.flush()

        parsed = _call_vision_reel(framesData, thumbnailData, metadata)
        filtered = [c for c in parsed.candidates if c.confidence >= CONFIDENCE_THRESHOLD]

        refined_title = _refined_title(parsed, title, filtered)
        category = _pipeline_category(filtered)
        estimated_minutes = 90
        prompt_version = get_reel_prompt_version()

        raw_output: dict = {
            "structured": parsed.model_dump(),
            "metadata": metadata,
        }

        pipeline_result = PipelineResultModel(
            ideaId=idea.id,
            jobId=UUID(jobId),
            source="reel",
            refinedTitle=refined_title,
            category=category,
            estimatedMinutes=estimated_minutes,
            modelName=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
            promptVersion=prompt_version,
            rawOutput=raw_output,
        )
        session.add(pipeline_result)
        session.flush()

        suggestions: list[tuple[PlaceSuggestionModel, float | None]] = []
        for candidate in filtered:
            if not _should_resolve_maps(candidate):
                continue

            query_key = (candidate.mapsQuery or candidate.title or "").strip()
            if not query_key:
                continue

            place_address = candidate.placeAddress
            category_cand = candidate.category
            confidence = candidate.confidence

            resolved = _resolveGoogleMaps(query_key, place_address) or {}
            place = _create_or_get_place(
                session,
                place_name=candidate.title or query_key,
                address=resolved.get("placeAddress", place_address),
                google_place_id=resolved.get("googlePlaceId"),
                category=category_cand,
                latitude=resolved.get("latitude"),
                longitude=resolved.get("longitude"),
            )
            if place:
                sugg = PlaceSuggestionModel(
                    resultId=pipeline_result.id,
                    placeId=place.id,
                    rawName=candidate.title or query_key,
                    confidence=confidence,
                )
                session.add(sugg)
                session.flush()
                suggestions.append((sugg, confidence))

        _auto_select_place(session, idea, suggestions)

        idea.status = IdeaStatus.ready
        idea.updatedAt = datetime.utcnow()
        session.add(idea)

        job.status = JobStatus.done
        job.updatedAt = datetime.utcnow()
        session.add(job)
        session.commit()

        logger.info(
            "reel_ingestion_complete",
            extra={
                "jobId": jobId,
                "ideaId": str(idea.id),
                "suggestionCount": len(suggestions),
                "candidateCount": len(parsed.candidates),
            },
        )
    except ProviderRateLimitError as e:
        logger.warning("reel_ingestion_rate_limited", extra={"jobId": jobId, "message": str(e)})
        try:
            job = session.get(IngestionJobModel, UUID(jobId))
            if job:
                job.status = JobStatus.failed
                job.error = str(e)
                job.updatedAt = datetime.utcnow()
                session.add(job)
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
                session.commit()
        except Exception:
            logger.exception("failed_to_update_job_status", extra={"jobId": jobId})
    finally:
        try:
            next(sessionGen, None)
        except StopIteration:
            pass
