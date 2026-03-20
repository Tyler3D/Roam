import logging
import re
from typing import Any, Optional

import httpx

from app.common.config import getGoogleMapsApiKey

logger = logging.getLogger("roam.places")

TYPE_DURATIONS: dict[str, int] = {
    "museum": 150, "art_gallery": 120, "park": 90, "restaurant": 90,
    "cafe": 60, "bar": 90, "night_club": 120, "movie_theater": 150,
    "shopping_mall": 120, "clothing_store": 60, "book_store": 60,
    "library": 90, "gym": 75, "spa": 120, "zoo": 180, "aquarium": 120,
    "amusement_park": 240, "bowling_alley": 90, "stadium": 180,
    "tourist_attraction": 120, "church": 60,
}

KEYWORD_DURATIONS: list[tuple[re.Pattern, int]] = [
    (re.compile(r"\b(museum|exhibit|gallery)\b", re.I), 150),
    (re.compile(r"\b(park|walk|hike|trail|garden)\b", re.I), 90),
    (re.compile(r"\b(restaurant|dinner|lunch|brunch|eat)\b", re.I), 90),
    (re.compile(r"\b(coffee|cafe|tea)\b", re.I), 60),
    (re.compile(r"\b(bar|drinks|cocktail|happy hour)\b", re.I), 90),
    (re.compile(r"\b(movie|film|cinema|theater)\b", re.I), 150),
    (re.compile(r"\b(shop|mall|store|market)\b", re.I), 120),
    (re.compile(r"\b(gym|workout|yoga|pilates|climb)\b", re.I), 75),
    (re.compile(r"\b(spa|massage)\b", re.I), 120),
    (re.compile(r"\b(zoo|aquarium)\b", re.I), 150),
    (re.compile(r"\b(concert|show|performance|play)\b", re.I), 150),
    (re.compile(r"\b(beach|swim|pool)\b", re.I), 120),
    (re.compile(r"\b(run|jog)\b", re.I), 45),
]


def estimate_duration(title: str, place_types: list[str] | None = None) -> int:
    for t in place_types or []:
        if t in TYPE_DURATIONS:
            return TYPE_DURATIONS[t]
    for pattern, minutes in KEYWORD_DURATIONS:
        if pattern.search(title):
            return minutes
    return 60


def _text_search_result_to_dict(top: dict[str, Any], query_fallback: str) -> dict[str, Any]:
    location = top.get("geometry", {}).get("location", {})
    types = top.get("types", [])
    opening_hours = top.get("opening_hours", {})
    return {
        "googlePlaceId": top.get("place_id"),
        "name": top.get("name", query_fallback),
        "address": top.get("formatted_address"),
        "city": _extract_city(top.get("formatted_address", "")),
        "latitude": location.get("lat"),
        "longitude": location.get("lng"),
        "category": _classify_place_types(types),
        "placeTypes": types,
        "openingHours": opening_hours.get("periods", []),
    }


def _google_text_search(query: str) -> list[dict[str, Any]]:
    api_key = getGoogleMapsApiKey()
    if not api_key:
        logger.warning("Google Maps API key not configured")
        return []
    try:
        with httpx.Client(timeout=10) as client:
            resp = client.get(
                "https://maps.googleapis.com/maps/api/place/textsearch/json",
                params={"query": query, "key": api_key},
            )
            resp.raise_for_status()
            data = resp.json()
        return list(data.get("results", []))
    except Exception:
        logger.exception("Google Places search failed", extra={"query": query})
        return []


def search_google_places(query: str) -> dict[str, Any] | None:
    results = _google_text_search(query)
    if not results:
        return None
    return _text_search_result_to_dict(results[0], query)


def search_google_places_many(query: str, *, limit: int = 8) -> list[dict[str, Any]]:
    """Top Text Search hits as place dicts (same shape as search_google_places)."""
    raw = _google_text_search(query)
    if not raw:
        return []
    out: list[dict[str, Any]] = []
    for top in raw[: max(1, min(limit, 15))]:
        out.append(_text_search_result_to_dict(top, query))
    return out


def _extract_city(address: str) -> str | None:
    parts = [p.strip() for p in address.split(",")]
    if len(parts) >= 3:
        return parts[-3]
    if len(parts) >= 2:
        return parts[-2]
    return None


def _classify_place_types(types: list[str]) -> str:
    type_map = {
        "restaurant": "food-drink", "cafe": "food-drink", "bakery": "food-drink",
        "bar": "nightlife", "night_club": "nightlife",
        "museum": "arts-culture", "art_gallery": "arts-culture",
        "park": "outdoors", "campground": "outdoors",
        "gym": "fitness", "stadium": "fitness",
        "shopping_mall": "shopping", "store": "shopping",
        "movie_theater": "entertainment", "amusement_park": "entertainment",
        "library": "learning", "university": "learning",
        "tourist_attraction": "travel",
    }
    for t in types:
        if t in type_map:
            return type_map[t]
    return "other"
