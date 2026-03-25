import logging
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import and_, func
from sqlmodel import Session, col, or_, select

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.collections import (
    CollectionCreate,
    CollectionIdeaModel,
    CollectionMapIdeaRead,
    CollectionMemberAddBody,
    CollectionMemberModel,
    CollectionMemberPreview,
    CollectionModel,
    CollectionPatch,
    CollectionRead,
)
from app.models.friendships import FriendshipModel, FriendshipStatus
from app.models.ideas import IdeaModel
from app.models.notifications import NotificationModel, NotificationType
from app.models.pipeline import PipelineResultModel
from app.models.places import PlaceModel
from app.models.users import UserModel
from app.services.collectionLinks import ensurePersonalDefaultCollection, userColorIndex

logger = logging.getLogger("roam.collections")

collectionsRouter = APIRouter()
_memberPreviewCap = 5


def _acceptedFriendsIds(session: Session, userId: UUID) -> set[UUID]:
    out: set[UUID] = set()
    rows = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.status == FriendshipStatus.accepted,
            or_(
                FriendshipModel.requesterId == userId,
                FriendshipModel.addresseeId == userId,
            ),
        )
    ).all()
    for f in rows:
        out.add(f.addresseeId if f.requesterId == userId else f.requesterId)
    return out


def _isMember(session: Session, collectionId: UUID, userId: UUID) -> bool:
    return (
        session.exec(
            select(CollectionMemberModel).where(
                CollectionMemberModel.collectionId == collectionId,
                CollectionMemberModel.userId == userId,
            )
        ).first()
        is not None
    )


def _memberPreviewsForCollections(
    session: Session, collection_ids: list[UUID]
) -> dict[UUID, list[CollectionMemberPreview]]:
    if not collection_ids:
        return {}
    members = session.exec(
        select(CollectionMemberModel)
        .where(CollectionMemberModel.collectionId.in_(collection_ids))
        .order_by(
            CollectionMemberModel.collectionId,
            col(CollectionMemberModel.joinedAt).asc(),
        )
    ).all()
    by_cid: dict[UUID, list[UUID]] = {}
    for m in members:
        lst = by_cid.setdefault(m.collectionId, [])
        if len(lst) < _memberPreviewCap:
            lst.append(m.userId)
    all_uids: set[UUID] = set()
    for lst in by_cid.values():
        all_uids.update(lst)
    user_map: dict[UUID, UserModel] = {}
    if all_uids:
        urows = session.exec(select(UserModel).where(col(UserModel.id).in_(all_uids))).all()
        user_map = {u.id: u for u in urows}
    out: dict[UUID, list[CollectionMemberPreview]] = {cid: [] for cid in collection_ids}
    for cid, uids in by_cid.items():
        prev: list[CollectionMemberPreview] = []
        for uid in uids:
            u = user_map.get(uid)
            prev.append(
                CollectionMemberPreview(
                    userId=uid,
                    firstName=u.firstName if u else "",
                    lastName=u.lastName if u else "",
                    photoUrl=u.photoUrl if u else None,
                )
            )
        out[cid] = prev
    return out


def _collectionToRead(session: Session, c: CollectionModel) -> CollectionRead:
    previews = _memberPreviewsForCollections(session, [c.id])
    return CollectionRead(
        id=c.id,
        creatorId=c.creatorId,
        name=c.name,
        description=c.description,
        isPersonalDefault=c.isPersonalDefault,
        createdAt=c.createdAt,
        memberPreview=previews.get(c.id, []),
    )


def _latestCategoryBatch(session: Session, idea_ids: list[UUID]) -> dict[UUID, str | None]:
    if not idea_ids:
        return {}
    subq = (
        select(
            PipelineResultModel.ideaId.label("iid"),
            func.max(PipelineResultModel.createdAt).label("mx"),
        )
        .where(col(PipelineResultModel.ideaId).in_(idea_ids))
        .group_by(PipelineResultModel.ideaId)
    ).subquery()
    pr_rows = session.exec(
        select(PipelineResultModel).join(
            subq,
            and_(
                PipelineResultModel.ideaId == subq.c.iid,
                PipelineResultModel.createdAt == subq.c.mx,
            ),
        )
    ).all()
    out: dict[UUID, str | None] = {iid: None for iid in idea_ids}
    seen: set[UUID] = set()
    for pr in pr_rows:
        if pr.ideaId and pr.ideaId not in seen:
            seen.add(pr.ideaId)
            out[pr.ideaId] = pr.category
    return out


def _ideasToMapReadBatch(session: Session, ideas: list[IdeaModel]) -> list[CollectionMapIdeaRead]:
    if not ideas:
        return []
    idea_ids = [i.id for i in ideas]
    cat_map = _latestCategoryBatch(session, idea_ids)
    place_ids = {i.placeId for i in ideas if i.placeId}
    user_ids = {i.userId for i in ideas}
    place_map: dict[UUID, PlaceModel] = {}
    if place_ids:
        pls = session.exec(select(PlaceModel).where(col(PlaceModel.id).in_(place_ids))).all()
        place_map = {p.id: p for p in pls}
    user_map: dict[UUID, UserModel] = {}
    if user_ids:
        us = session.exec(select(UserModel).where(col(UserModel.id).in_(user_ids))).all()
        user_map = {u.id: u for u in us}
    out: list[CollectionMapIdeaRead] = []
    for idea in ideas:
        placeName = placeAddress = None
        lat = lng = None
        if idea.placeId and idea.placeId in place_map:
            pl = place_map[idea.placeId]
            placeName = pl.name
            placeAddress = pl.address
            lat = pl.latitude
            lng = pl.longitude
        owner = user_map.get(idea.userId)
        fn = owner.firstName if owner else ""
        ln = owner.lastName if owner else ""
        out.append(
            CollectionMapIdeaRead(
                id=idea.id,
                title=idea.title,
                notes=idea.notes,
                displayName=idea.displayName,
                placeId=idea.placeId,
                placeName=placeName,
                placeAddress=placeAddress,
                placeLatitude=lat,
                placeLongitude=lng,
                category=cat_map.get(idea.id),
                createdAt=idea.createdAt,
                addedByUserId=idea.userId,
                addedByFirstName=fn,
                addedByLastName=ln,
                addedByColorIndex=userColorIndex(idea.userId),
            )
        )
    return out


def _ideasVisibleInCollection(session: Session, collectionId: UUID) -> list[IdeaModel]:
    rows = session.exec(
        select(CollectionIdeaModel.ideaId).where(CollectionIdeaModel.collectionId == collectionId)
    ).all()
    if not rows:
        return []
    ideas = list(session.exec(select(IdeaModel).where(col(IdeaModel.id).in_(rows))).all())
    ideas.sort(key=lambda i: i.createdAt, reverse=True)
    return ideas


def _ideasEverythingForUser(session: Session, userId: UUID) -> list[IdeaModel]:
    idea_ids = session.exec(
        select(CollectionIdeaModel.ideaId)
        .join(
            CollectionMemberModel,
            CollectionMemberModel.collectionId == CollectionIdeaModel.collectionId,
        )
        .where(CollectionMemberModel.userId == userId)
    ).all()
    unique: list[UUID] = []
    seen: set[UUID] = set()
    for iid in idea_ids:
        if iid not in seen:
            seen.add(iid)
            unique.append(iid)
    if not unique:
        return []
    ideas = list(session.exec(select(IdeaModel).where(col(IdeaModel.id).in_(unique))).all())
    ideas.sort(key=lambda i: i.createdAt, reverse=True)
    return ideas


@collectionsRouter.get("/collections/everything/ideas", response_model=list[CollectionMapIdeaRead])
def listEverythingMapIdeas(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[CollectionMapIdeaRead]:
    ensurePersonalDefaultCollection(session, user.id)
    session.commit()
    ideas = _ideasEverythingForUser(session, user.id)
    return _ideasToMapReadBatch(session, ideas)


@collectionsRouter.get("/collections", response_model=list[CollectionRead])
def listCollections(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[CollectionRead]:
    ensurePersonalDefaultCollection(session, user.id)
    session.flush()
    collIds = session.exec(
        select(CollectionMemberModel.collectionId).where(CollectionMemberModel.userId == user.id)
    ).all()
    if not collIds:
        session.commit()
        return []
    collections = list(
        session.exec(select(CollectionModel).where(col(CollectionModel.id).in_(collIds))).all()
    )
    collections.sort(
        key=lambda x: (not x.isPersonalDefault, x.createdAt),
    )
    session.commit()
    preview_map = _memberPreviewsForCollections(session, [c.id for c in collections])
    return [
        CollectionRead(
            id=c.id,
            creatorId=c.creatorId,
            name=c.name,
            description=c.description,
            isPersonalDefault=c.isPersonalDefault,
            createdAt=c.createdAt,
            memberPreview=preview_map.get(c.id, []),
        )
        for c in collections
    ]


@collectionsRouter.post("/collections", response_model=CollectionRead, status_code=201)
def createSharedCollection(
    body: CollectionCreate,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> CollectionRead:
    name = body.name.strip()
    if not name:
        raise BadRequest("name is required")
    friends = _acceptedFriendsIds(session, user.id)

    coll = CollectionModel(
        creatorId=user.id,
        name=name[:500],
        description=(body.description or "")[:2000] if body.description else None,
        isPersonalDefault=False,
    )
    session.add(coll)
    session.flush()
    session.add(CollectionMemberModel(collectionId=coll.id, userId=user.id))

    inviter = user
    for uid in body.memberUserIds:
        if uid == user.id:
            continue
        if uid not in friends:
            raise BadRequest("Can only add friends to a collection")
        session.add(CollectionMemberModel(collectionId=coll.id, userId=uid))
        note = NotificationModel(
            userId=uid,
            type=NotificationType.added_to_collection,
            collectionId=coll.id,
            title=f"{inviter.firstName or 'Someone'} added you to {coll.name}",
            body=None,
        )
        session.add(note)

    commitAndRefresh(session, coll)
    return _collectionToRead(session, coll)


@collectionsRouter.patch("/collections/{collectionId}", response_model=CollectionRead)
def patchCollection(
    collectionId: UUID,
    body: CollectionPatch,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> CollectionRead:
    c = session.get(CollectionModel, collectionId)
    if not c:
        raise NotFound("Collection not found")
    if not _isMember(session, collectionId, user.id):
        raise Forbidden("Not a member of this collection")

    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        c.name = str(data["name"]).strip()[:500]
    if "description" in data:
        c.description = (
            (str(data["description"])[:2000] if data["description"] is not None else None)
        )

    session.add(c)
    commitAndRefresh(session, c)
    return _collectionToRead(session, c)


@collectionsRouter.delete("/collections/{collectionId}", status_code=204)
def deleteCollection(
    collectionId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    c = session.get(CollectionModel, collectionId)
    if not c:
        raise NotFound("Collection not found")
    if c.isPersonalDefault:
        raise BadRequest("Cannot delete your personal collection")
    if c.creatorId != user.id:
        raise Forbidden("Only the creator can delete this collection")
    session.delete(c)
    session.commit()


@collectionsRouter.post("/collections/{collectionId}/members", status_code=204)
def addCollectionMember(
    collectionId: UUID,
    body: CollectionMemberAddBody,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    c = session.get(CollectionModel, collectionId)
    if not c:
        raise NotFound("Collection not found")
    if c.isPersonalDefault:
        raise BadRequest("Cannot add members to your personal collection")
    if not _isMember(session, collectionId, user.id):
        raise Forbidden("Not a member of this collection")

    newMemberId = body.userId
    if newMemberId == user.id:
        raise BadRequest("Already a member")
    exists = session.exec(
        select(CollectionMemberModel).where(
            CollectionMemberModel.collectionId == collectionId,
            CollectionMemberModel.userId == newMemberId,
        )
    ).first()
    if exists:
        return

    friends = _acceptedFriendsIds(session, user.id)
    if newMemberId not in friends:
        raise BadRequest("Can only add friends to a collection")

    session.add(CollectionMemberModel(collectionId=collectionId, userId=newMemberId))
    session.add(
        NotificationModel(
            userId=newMemberId,
            type=NotificationType.added_to_collection,
            collectionId=c.id,
            title=f"{user.firstName or 'Someone'} added you to {c.name}",
            body=None,
        )
    )
    session.commit()


@collectionsRouter.delete("/collections/{collectionId}/members/{memberUserId}", status_code=204)
def removeCollectionMember(
    collectionId: UUID,
    memberUserId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    c = session.get(CollectionModel, collectionId)
    if not c:
        raise NotFound("Collection not found")
    if c.isPersonalDefault:
        raise BadRequest("Cannot change membership of your personal collection")
    if not _isMember(session, collectionId, user.id):
        raise Forbidden("Not a member of this collection")

    if memberUserId != user.id and not _isMember(session, collectionId, memberUserId):
        raise NotFound("Member not found")

    if memberUserId != user.id:
        # any member may remove another
        pass
    row = session.exec(
        select(CollectionMemberModel).where(
            CollectionMemberModel.collectionId == collectionId,
            CollectionMemberModel.userId == memberUserId,
        )
    ).first()
    if not row:
        raise NotFound("Member not found")
    session.delete(row)
    session.commit()


@collectionsRouter.get("/collections/{collectionId}/ideas", response_model=list[CollectionMapIdeaRead])
def listCollectionMapIdeas(
    collectionId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[CollectionMapIdeaRead]:
    c = session.get(CollectionModel, collectionId)
    if not c:
        raise NotFound("Collection not found")
    if not _isMember(session, collectionId, user.id):
        raise Forbidden("Not a member of this collection")
    ideas = _ideasVisibleInCollection(session, collectionId)
    return _ideasToMapReadBatch(session, ideas)
