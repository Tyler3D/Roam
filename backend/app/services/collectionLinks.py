"""Personal default collection + linking ideas to collections (server invariants)."""
from __future__ import annotations

import logging
from uuid import UUID

from sqlmodel import Session, col, select

from app.common.backendErrors import BadRequest
from app.models.collections import CollectionIdeaModel, CollectionMemberModel, CollectionModel
from app.models.ideas import IdeaModel
from app.models.places import PlaceModel
from app.models.users import UserModel

logger = logging.getLogger("roam.collection_links")


def userColorIndex(userId: UUID) -> int:
    return userId.int % 8


def ensurePersonalDefaultCollection(session: Session, userId: UUID) -> CollectionModel:
    row = session.exec(
        select(CollectionModel).where(
            CollectionModel.creatorId == userId,
            CollectionModel.isPersonalDefault == True,  # noqa: E712
        )
    ).first()
    if row:
        return row
    coll = CollectionModel(
        creatorId=userId,
        name="My saves",
        isPersonalDefault=True,
    )
    session.add(coll)
    session.flush()
    session.add(CollectionMemberModel(collectionId=coll.id, userId=userId))
    session.flush()
    return coll


def isCollectionMember(session: Session, collectionId: UUID, userId: UUID) -> bool:
    m = session.exec(
        select(CollectionMemberModel).where(
            CollectionMemberModel.collectionId == collectionId,
            CollectionMemberModel.userId == userId,
        )
    ).first()
    return m is not None


def _ensureCollectionIdeaRow(session: Session, collectionId: UUID, ideaId: UUID) -> None:
    existing = session.exec(
        select(CollectionIdeaModel).where(
            CollectionIdeaModel.collectionId == collectionId,
            CollectionIdeaModel.ideaId == ideaId,
        )
    ).first()
    if existing:
        return
    session.add(CollectionIdeaModel(collectionId=collectionId, ideaId=ideaId))
    session.flush()


def linkIdeaToPersonalAndShared(
    session: Session,
    *,
    ideaId: UUID,
    ownerUserId: UUID,
    sharedCollectionIds: list[UUID] | None,
) -> None:
    """Link the idea to the owner's personal default collection, then optional shared collections.

    Invariant (reels and manual idea creation): every new idea is always in the owner's
    personal default collection. ``sharedCollectionIds`` must name *additional* shared
    collections only; the owner's personal default UUID is ignored if the client sends it.
    """
    personal = ensurePersonalDefaultCollection(session, ownerUserId)
    _ensureCollectionIdeaRow(session, personal.id, ideaId)

    raw = [x for x in (sharedCollectionIds or []) if x != personal.id]
    if not raw:
        return

    seen: set[UUID] = set()
    for sharedCollectionId in raw:
        if sharedCollectionId in seen:
            continue
        seen.add(sharedCollectionId)
        coll = session.get(CollectionModel, sharedCollectionId)
        if coll is None:
            raise BadRequest("Unknown collection in collectionIds")
        if coll.isPersonalDefault:
            continue
        if not isCollectionMember(session, sharedCollectionId, ownerUserId):
            raise BadRequest("Not a member of one or more collections")
        _ensureCollectionIdeaRow(session, sharedCollectionId, ideaId)
        _notifyCollectionIdeaAdded(session, sharedCollectionId, ideaId, ownerUserId)


def _notifyCollectionIdeaAdded(
    session: Session, collectionId: UUID, ideaId: UUID, adderUserId: UUID
) -> None:
    """Send push to all collection members when an idea is added to a shared collection."""
    try:
        from app.services.notifications import notifyCollectionIdeaAdded

        coll = session.get(CollectionModel, collectionId)
        if not coll or coll.isPersonalDefault:
            return
        idea = session.get(IdeaModel, ideaId)
        adder = session.get(UserModel, adderUserId)
        placeName = None
        if idea and idea.placeId:
            place = session.get(PlaceModel, idea.placeId)
            placeName = place.name if place else None

        members = session.exec(
            select(CollectionMemberModel.userId).where(
                CollectionMemberModel.collectionId == collectionId
            )
        ).all()

        notifyCollectionIdeaAdded(
            session,
            collectionId=collectionId,
            ideaId=ideaId,
            placeName=placeName,
            adderUserId=adderUserId,
            adderFirstName=adder.firstName if adder else "",
            collectionName=coll.name,
            memberUserIds=list(members),
        )
    except Exception:
        logger.exception("collection_idea_notification_failed")
