import logging
import re
from typing import Any, Optional

import httpx

from app.common.backendErrors import ProviderRateLimitError
from app.common.config import getGoogleMapsApiKey
from app.common.idea_categories import normalize_category

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
    place_id = top.get("place_id")
    formatted_address = top.get("formatted_address", "")
    return {
        "googlePlaceId": place_id,
        "name": top.get("name", query_fallback),
        "address": formatted_address,
        "city": extractCity(place_id, formatted_address),
        "latitude": location.get("lat"),
        "longitude": location.get("lng"),
        "category": _classify_place_types(types),
        "placeTypes": types,
        "openingHours": opening_hours.get("periods", []),
    }


def _googleTextSearch(query: str) -> list[dict[str, Any]]:
    apiKey = getGoogleMapsApiKey()
    if not apiKey:
        logger.warning("Google Maps API key not configured")
        return []
    with httpx.Client(timeout=10) as client:
        resp = client.get(
            "https://maps.googleapis.com/maps/api/place/textsearch/json",
            params={"query": query, "key": apiKey},
        )
        if resp.status_code == 429:
            raise ProviderRateLimitError("Google Maps rate limit exceeded; try again later.")
        resp.raise_for_status()
        data = resp.json()
    return list(data.get("results", []))


def search_google_places(query: str) -> dict[str, Any] | None:
    results = _googleTextSearch(query)
    if not results:
        return None
    return _text_search_result_to_dict(results[0], query)


def search_google_places_many(query: str, *, limit: int = 8) -> list[dict[str, Any]]:
    """Top Text Search hits as place dicts (same shape as search_google_places)."""
    raw = _googleTextSearch(query)
    if not raw:
        return []
    out: list[dict[str, Any]] = []
    for top in raw[: max(1, min(limit, 15))]:
        out.append(_text_search_result_to_dict(top, query))
    return out


def resolveGoogleTextSearch(
    placeName: str, placeAddress: str | None
) -> dict[str, Any] | None:
    """Resolve a place via Google Text Search — returns the full place dict.

    Raises ProviderRateLimitError on 429.  Returns the same rich dict shape
    as search_google_places (includes placeTypes, openingHours, city, etc.).
    """
    query = placeName
    if placeAddress:
        query = f"{placeName} {placeAddress}"
    results = _googleTextSearch(query)
    if not results:
        return None
    return _text_search_result_to_dict(results[0], placeName)


def _geocodePlaceId(placeId: str) -> list[dict[str, Any]]:
    """Geocoding API lookup by placeId → address_components list."""
    apiKey = getGoogleMapsApiKey()
    if not apiKey:
        return []
    with httpx.Client(timeout=10) as client:
        resp = client.get(
            "https://maps.googleapis.com/maps/api/geocode/json",
            params={"place_id": placeId, "key": apiKey},
        )
        resp.raise_for_status()
        data = resp.json()
    results = data.get("results", [])
    if not results:
        return []
    return results[0].get("address_components", [])


def _extractCityFromComponents(components: list[dict[str, Any]]) -> str | None:
    """Pull the city from Google's structured address_components.

    Tries 'locality' first, then common fallbacks for cities that Google
    categorises differently (e.g. Tokyo → administrative_area_level_1).
    """
    for targetType in ("locality", "sublocality_level_1", "sublocality",
                       "administrative_area_level_2", "administrative_area_level_1"):
        for comp in components:
            if targetType in comp.get("types", []):
                return comp.get("long_name")
    return None


def _extractCityHeuristic(address: str) -> str | None:
    """Best-effort city guess from a formatted address string."""
    parts = [p.strip() for p in address.split(",")]
    if len(parts) >= 3:
        return parts[-3]
    if len(parts) >= 2:
        return parts[-2]
    return None


def extractCity(placeId: str | None, formattedAddress: str = "") -> str | None:
    """Extract city for a place — structured components when possible, heuristic fallback."""
    if placeId:
        components = _geocodePlaceId(placeId)
        city = _extractCityFromComponents(components)
        if city:
            return city
    return _extractCityHeuristic(formattedAddress)


def _classify_place_types(types: list[str]) -> str:
    type_map = {
        "restaurant": "restaurant",
        "cafe": "cafe",
        "bakery": "cafe",
        "bar": "bar",
        "liquor_store": "bar",
        "night_club": "nightlife",
        "museum": "arts-culture",
        "art_gallery": "arts-culture",
        "park": "outdoors",
        "campground": "outdoors",
        "gym": "fitness",
        "stadium": "fitness",
        "shopping_mall": "shopping",
        "store": "shopping",
        "movie_theater": "entertainment",
        "amusement_park": "entertainment",
        "library": "learning",
        "university": "learning",
        "tourist_attraction": "travel",
    }
    for t in types:
        if t in type_map:
            return normalize_category(type_map[t])
    return "other"
