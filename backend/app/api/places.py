import logging
from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, select

from app.auth.auth import getCurrentUser
from app.common.db import getSession
from app.common.idea_categories import normalize_category
from app.models.places import PlaceModel, PlaceRead
from app.models.users import UserModel
from app.services.places import estimateDuration, searchGooglePlaces, searchGooglePlacesMany

logger = logging.getLogger("roam.places")
placesRouter = APIRouter()


def _backfillPlace(session: Session, place: PlaceModel, data: dict) -> None:
    """Fill in null fields on an existing place from richer data."""
    updated = False
    if not place.city and data.get("city"):
        place.city = data["city"]
        updated = True
    if not place.openingHours and data.get("openingHours"):
        place.openingHours = data["openingHours"]
        updated = True
    if not place.placeTypes and data.get("placeTypes"):
        place.placeTypes = data["placeTypes"]
        updated = True
    if not place.category and data.get("category"):
        place.category = normalize_category(data["category"])
        updated = True
    if updated:
        session.add(place)
        session.flush()


def _getOrCreatePlaceRead(session: Session, place_data: dict, fallback_name: str) -> PlaceRead:
    google_place_id = place_data.get("googlePlaceId")
    if google_place_id:
        existing = session.exec(
            select(PlaceModel).where(PlaceModel.googlePlaceId == google_place_id)
        ).first()
        if existing:
            _backfillPlace(session, existing, place_data)
            read = PlaceRead.model_validate(existing)
            read.estimatedMinutes = estimateDuration(
                existing.name, existing.placeTypes or []
            )
            return read

    raw_cat = place_data.get("category")
    place_cat = (
        normalize_category(raw_cat)
        if raw_cat is not None and str(raw_cat).strip()
        else None
    )
    place = PlaceModel(
        googlePlaceId=google_place_id,
        name=place_data.get("name", fallback_name),
        address=place_data.get("address"),
        city=place_data.get("city"),
        latitude=place_data.get("latitude"),
        longitude=place_data.get("longitude"),
        category=place_cat,
        placeTypes=place_data.get("placeTypes", []),
        openingHours=place_data.get("openingHours", []),
    )
    session.add(place)
    session.commit()
    session.refresh(place)

    read = PlaceRead.model_validate(place)
    read.estimatedMinutes = estimateDuration(
        place.name, place.placeTypes or []
    )
    return read


@placesRouter.get("/places/search", response_model=PlaceRead | None)
def searchPlaces(
    q: str = Query(..., min_length=2),
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> PlaceRead | None:
    place_data = searchGooglePlaces(q)
    if not place_data:
        return None
    return _getOrCreatePlaceRead(session, place_data, q)


@placesRouter.get("/places/search-list", response_model=list[PlaceRead])
def searchPlacesList(
    q: str = Query(..., min_length=2),
    limit: int = Query(default=8, ge=1, le=15),
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[PlaceRead]:
    rows = searchGooglePlacesMany(q, limit=limit)
    out: list[PlaceRead] = []
    for place_data in rows:
        out.append(_getOrCreatePlaceRead(session, place_data, q))
    return out
