"""Personal default collection + linking ideas to collections (server invariants)."""
from __future__ import annotations

from uuid import UUID

from sqlmodel import Session, col, select

from app.common.backendErrors import BadRequest
from app.models.collections import CollectionIdeaModel, CollectionMemberModel, CollectionModel


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
