import base64
import json
import logging
from datetime import datetime
from uuid import UUID

import httpx
from openai import OpenAI

from app.common.config import getOpenAIApiKey, getGoogleMapsApiKey

# Raised when OpenAI or Google Maps returns 429 / rate limit; job should fail with clear message
class ProviderRateLimitError(Exception):
    pass
from app.common.db import getSession
from app.models.ingestion import ExtractionModel, IngestionJobModel, JobStatus

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


def _buildUserMessage(framesData: list[bytes], thumbnailData: bytes | None, metadata: dict) -> list[dict]:
    content: list[dict] = []

    textParts = []
    if metadata.get("lpTitle"):
        textParts.append(f"Title: {metadata['lpTitle']}")
    if metadata.get("ogDescription"):
        textParts.append(f"Description: {metadata['ogDescription']}")
    if metadata.get("ogKeywords"):
        textParts.append(f"Keywords: {metadata['ogKeywords']}")
    if metadata.get("shareText"):
        textParts.append(f"Caption/Share text: {metadata['shareText']}")
    if metadata.get("reelUrl"):
        textParts.append(f"URL: {metadata['reelUrl']}")

    if textParts:
        content.append({"type": "text", "text": "\n".join(textParts)})

    allImages = []
    if thumbnailData:
        allImages.append(thumbnailData)
    allImages.extend(framesData)

    for imgBytes in allImages:
        b64 = base64.b64encode(imgBytes).decode("utf-8")
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{b64}", "detail": "low"},
        })

    if not content:
        content.append({"type": "text", "text": "No metadata or images available."})

    return content


def _callVisionLLM(framesData: list[bytes], thumbnailData: bytes | None, metadata: dict) -> list[dict]:
    client = OpenAI(api_key=getOpenAIApiKey())

    userContent = _buildUserMessage(framesData, thumbnailData, metadata)

    try:
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": userContent},
            ],
            max_tokens=1024,
            temperature=0.2,
        )
    except Exception as e:
        if getattr(e, "status_code", None) == 429 or "rate" in str(e).lower():
            raise ProviderRateLimitError("OpenAI rate limit exceeded; try again later.") from e
        raise

    raw = response.choices[0].message.content or "[]"

    # Strip markdown fences if present
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        lines = lines[1:]  # drop opening fence
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

        candidates = _callVisionLLM(framesData, thumbnailData, metadata)
        filtered = [c for c in candidates if c.get("confidence", 0) >= CONFIDENCE_THRESHOLD]

        for candidate in filtered:
            placeName = candidate.get("placeName", "")
            placeAddress = candidate.get("placeAddress")
            category = candidate.get("category")
            confidence = candidate.get("confidence")

            resolved = _resolveGoogleMaps(placeName, placeAddress) or {}

            extraction = ExtractionModel(
                jobId=UUID(jobId),
                placeName=placeName,
                placeAddress=resolved.get("placeAddress", placeAddress),
                category=category,
                latitude=resolved.get("latitude"),
                longitude=resolved.get("longitude"),
                googlePlaceId=resolved.get("googlePlaceId"),
                confidence=confidence,
                rawLlmOutput=candidate,
            )
            session.add(extraction)

        job.status = JobStatus.done
        job.updatedAt = datetime.utcnow()
        session.add(job)
        session.commit()

        logger.info(
            "processing_complete",
            extra={"jobId": jobId, "extractionCount": len(filtered), "candidateCount": len(candidates)},
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
