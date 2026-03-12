import logging
from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, select

from app.auth.auth import getCurrentUser
from app.common.db import getSession
from app.models.places import PlaceModel, PlaceRead
from app.models.users import UserModel
from app.services.places import search_google_places, estimate_duration

logger = logging.getLogger("roam.places")
placesRouter = APIRouter()


@placesRouter.get("/places/search", response_model=PlaceRead | None)
def searchPlaces(
    q: str = Query(..., min_length=2),
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> PlaceRead | None:
    place_data = search_google_places(q)
    if not place_data:
        return None

    google_place_id = place_data.get("googlePlaceId")
    if google_place_id:
        existing = session.exec(
            select(PlaceModel).where(PlaceModel.googlePlaceId == google_place_id)
        ).first()
        if existing:
            read = PlaceRead.model_validate(existing)
            read.estimatedMinutes = estimate_duration(
                existing.name, existing.placeTypes or []
            )
            return read

    place = PlaceModel(
        googlePlaceId=google_place_id,
        name=place_data.get("name", q),
        address=place_data.get("address"),
        city=place_data.get("city"),
        latitude=place_data.get("latitude"),
        longitude=place_data.get("longitude"),
        category=place_data.get("category"),
        placeTypes=place_data.get("placeTypes", []),
        openingHours=place_data.get("openingHours", []),
    )
    session.add(place)
    session.commit()
    session.refresh(place)

    read = PlaceRead.model_validate(place)
    read.estimatedMinutes = estimate_duration(
        place.name, place.placeTypes or []
    )
    return read
