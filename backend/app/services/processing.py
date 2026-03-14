import json
import logging
import os
from datetime import datetime
from uuid import UUID

import httpx
from google import genai
from google.genai import types
from sqlmodel import Session, select

from app.common.config import getGeminiApiKey, getGoogleMapsApiKey

# Raised when OpenAI or Google Maps returns 429 / rate limit; job should fail with clear message
class ProviderRateLimitError(Exception):
    pass
from app.common.db import getSession
from app.models.ideas import IdeaModel, IdeaStatus
from app.models.ingestion import IngestionJobModel, JobStatus
from app.models.pipeline import PipelineResultModel, PlaceSuggestionModel
from app.models.places import PlaceModel

logger = logging.getLogger("roam.processing")

CONFIDENCE_THRESHOLD = 0.7

SYSTEM_PROMPT = """You are an expert at analyzing social media content (Instagram reels) to identify places, restaurants, bars, activities, and locations mentioned or shown.

Given a set of video frames and metadata from an Instagram reel, identify ALL places, businesses, or activities mentioned or visible. For each, provide:
- placeName: the name of the place or business
- placeAddress: any address or location hint (city, neighborhood, etc.)
- category: one of: restaurant, bar, cafe, hike, beach, park, museum, hotel, shop, nightclub, activity, or other
- confidence: 0.0 to 1.0 how confident you are this place is actually featured

Return a JSON array. Return ALL candidates — do not self-filter. Example:
[
  {"placeName": "Joe's Pizza", "placeAddress": "New York, NY", "category": "restaurant", "confidence": 0.9},
  {"placeName": "Central Park", "placeAddress": "Manhattan, NY", "category": "park", "confidence": 0.6}
]

If you cannot identify any places, return an empty array: []"""


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
        parts.append(types.Part.from_text("\n".join(text_parts)))

    all_images = []
    if thumbnailData:
        all_images.append(thumbnailData)
    all_images.extend(framesData)

    for img_bytes in all_images:
        parts.append(types.Part.from_bytes(data=img_bytes, mime_type="image/jpeg"))

    if not parts:
        parts.append(types.Part.from_text("No metadata or images available."))

    return parts


def _callVisionLLM(framesData: list[bytes], thumbnailData: bytes | None, metadata: dict) -> list[dict]:
    client = genai.Client(api_key=getGeminiApiKey())
    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

    contents = _build_gemini_contents(framesData, thumbnailData, metadata)

    try:
        response = client.models.generate_content(
            model=model,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type="application/json",
                temperature=0.2,
                max_output_tokens=1024,
            ),
        )
    except Exception as e:
        if getattr(e, "status_code", None) == 429 or "rate" in str(e).lower():
            raise ProviderRateLimitError("Gemini rate limit exceeded; try again later.") from e
        raise

    raw = response.text or "[]"

    # Strip markdown fences if present
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines)

    try:
        result = json.loads(cleaned)
        if not isinstance(result, list):
            logger.warning("LLM returned non-list JSON", extra={"raw": raw[:200]})
            return []
        return result
    except json.JSONDecodeError:
        logger.error("Failed to parse LLM JSON", extra={"raw": raw[:200]})
        return []


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
    logger.info("processing_start", extra={"jobId": jobId})

    sessionGen = getSession()
    session = next(sessionGen)

    try:
        job = session.get(IngestionJobModel, UUID(jobId))
        if not job:
            logger.error("Job not found", extra={"jobId": jobId})
            return

        title = metadata.get("reelTitle") or metadata.get("shareText") or "Untitled reel"
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

        candidates = _callVisionLLM(framesData, thumbnailData, metadata)
        filtered = [c for c in candidates if c.get("confidence", 0) >= CONFIDENCE_THRESHOLD]

        first = filtered[0] if filtered else {}
        refined_title = first.get("placeName") or title
        category = first.get("category")
        estimated_minutes = 90

        pipeline_result = PipelineResultModel(
            ideaId=idea.id,
            jobId=UUID(jobId),
            source="reel",
            refinedTitle=refined_title,
            category=category,
            estimatedMinutes=estimated_minutes,
            modelName=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
            rawOutput={"candidates": candidates, "metadata": metadata},
        )
        session.add(pipeline_result)
        session.flush()

        suggestions: list[tuple[PlaceSuggestionModel, float | None]] = []
        for candidate in filtered:
            placeName = candidate.get("placeName", "")
            placeAddress = candidate.get("placeAddress")
            category_cand = candidate.get("category")
            confidence = candidate.get("confidence", 0.0)

            resolved = _resolveGoogleMaps(placeName, placeAddress) or {}
            place = _create_or_get_place(
                session,
                place_name=placeName,
                address=resolved.get("placeAddress", placeAddress),
                google_place_id=resolved.get("googlePlaceId"),
                category=category_cand,
                latitude=resolved.get("latitude"),
                longitude=resolved.get("longitude"),
            )
            if place:
                sugg = PlaceSuggestionModel(
                    resultId=pipeline_result.id,
                    placeId=place.id,
                    rawName=placeName,
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
            "processing_complete",
            extra={"jobId": jobId, "ideaId": str(idea.id), "suggestionCount": len(suggestions), "candidateCount": len(candidates)},
        )
    except ProviderRateLimitError as e:
        logger.warning("processing_rate_limited", extra={"jobId": jobId, "message": str(e)})
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
        logger.exception("processing_failed", extra={"jobId": jobId})
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
