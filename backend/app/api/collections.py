import logging
from uuid import UUID

from fastapi import APIRouter, Depends
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


def _memberPreview(session: Session, collectionId: UUID) -> list[CollectionMemberPreview]:
    members = session.exec(
        select(CollectionMemberModel).where(CollectionMemberModel.collectionId == collectionId)
    ).all()
    out: list[CollectionMemberPreview] = []
    for m in members[:_memberPreviewCap]:
        u = session.get(UserModel, m.userId)
        out.append(
            CollectionMemberPreview(
                userId=m.userId,
                firstName=u.firstName if u else "",
                lastName=u.lastName if u else "",
                photoUrl=u.photoUrl if u else None,
            )
        )
    return out


def _collectionToRead(session: Session, c: CollectionModel) -> CollectionRead:
    return CollectionRead(
        id=c.id,
        creatorId=c.creatorId,
        name=c.name,
        description=c.description,
        isPersonalDefault=c.isPersonalDefault,
        createdAt=c.createdAt,
        memberPreview=_memberPreview(session, c.id),
    )


def _latestCategory(session: Session, ideaId: UUID) -> str | None:
    pr = session.exec(
        select(PipelineResultModel)
        .where(PipelineResultModel.ideaId == ideaId)
        .order_by(col(PipelineResultModel.createdAt).desc())
        .limit(1)
    ).first()
    return pr.category if pr else None


def _ideaToMapRead(session: Session, idea: IdeaModel) -> CollectionMapIdeaRead:
    placeName = None
    placeAddress = None
    lat = None
    lng = None
    if idea.placeId:
        pl = session.get(PlaceModel, idea.placeId)
        if pl:
            placeName = pl.name
            placeAddress = pl.address
            lat = pl.latitude
            lng = pl.longitude
    owner = session.get(UserModel, idea.userId)
    fn = owner.firstName if owner else ""
    ln = owner.lastName if owner else ""
    return CollectionMapIdeaRead(
        id=idea.id,
        title=idea.title,
        notes=idea.notes,
        displayName=idea.displayName,
        placeId=idea.placeId,
        placeName=placeName,
        placeAddress=placeAddress,
        placeLatitude=lat,
        placeLongitude=lng,
        category=_latestCategory(session, idea.id),
        createdAt=idea.createdAt,
        addedByUserId=idea.userId,
        addedByFirstName=fn,
        addedByLastName=ln,
        addedByColorIndex=userColorIndex(idea.userId),
    )


def _ideasVisibleInCollection(session: Session, collectionId: UUID) -> list[IdeaModel]:
    links = session.exec(
        select(CollectionIdeaModel).where(CollectionIdeaModel.collectionId == collectionId)
    ).all()
    ideas: list[IdeaModel] = []
    for link in links:
        idea = session.get(IdeaModel, link.ideaId)
        if idea:
            ideas.append(idea)
    ideas.sort(key=lambda i: i.createdAt, reverse=True)
    return ideas


def _ideasEverythingForUser(session: Session, userId: UUID) -> list[IdeaModel]:
    ideaIds = session.exec(
        select(CollectionIdeaModel.ideaId)
        .join(
            CollectionMemberModel,
            CollectionMemberModel.collectionId == CollectionIdeaModel.collectionId,
        )
        .where(CollectionMemberModel.userId == userId)
    ).all()
    seen: dict[UUID, IdeaModel] = {}
    for ideaId in ideaIds:
        if ideaId in seen:
            continue
        idea = session.get(IdeaModel, ideaId)
        if idea:
            seen[ideaId] = idea
    return sorted(seen.values(), key=lambda i: i.createdAt, reverse=True)


@collectionsRouter.get("/collections/everything/ideas", response_model=list[CollectionMapIdeaRead])
def listEverythingMapIdeas(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[CollectionMapIdeaRead]:
    ensurePersonalDefaultCollection(session, user.id)
    session.commit()
    ideas = _ideasEverythingForUser(session, user.id)
    return [_ideaToMapRead(session, i) for i in ideas]


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
    collections: list[CollectionModel] = []
    for cid in collIds:
        c = session.get(CollectionModel, cid)
        if c:
            collections.append(c)
    collections.sort(
        key=lambda x: (not x.isPersonalDefault, x.createdAt),
    )
    session.commit()
    return [_collectionToRead(session, c) for c in collections]


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
    return [_ideaToMapRead(session, i) for i in ideas]
