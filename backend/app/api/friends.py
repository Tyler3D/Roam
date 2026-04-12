import logging
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlmodel import Session, select, col, or_

from app.auth.auth import getCurrentUser
from app.common.backendErrors import BadRequest, Conflict, Forbidden, NotFound
from app.common.db import commitAndRefresh, getSession
from app.models.friendships import FriendshipModel, FriendshipRead, FriendshipStatus
from app.models.users import UserModel, UserRead
from app.services.notifications import notifyFriendRequestAccepted, notifyFriendRequestReceived

logger = logging.getLogger("roam.friends")
friendsRouter = APIRouter()


class FriendRequest(BaseModel):
    targetUserId: UUID


class FriendSearchResult(BaseModel):
    friends: list[UserRead]
    others: list[UserRead]


@friendsRouter.get("/friends", response_model=list[FriendshipRead])
def listFriends(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[FriendshipRead]:
    friendships = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.status == FriendshipStatus.accepted,
            or_(
                FriendshipModel.requesterId == user.id,
                FriendshipModel.addresseeId == user.id,
            ),
        )
    ).all()

    results: list[FriendshipRead] = []
    for f in friendships:
        read = FriendshipRead.model_validate(f)
        friend_id = f.addresseeId if f.requesterId == user.id else f.requesterId
        read.friendId = friend_id
        friend = session.get(UserModel, friend_id)
        if friend:
            read.friendFirstName = friend.firstName
            read.friendLastName = friend.lastName
            read.friendPhotoUrl = friend.photoUrl
        results.append(read)
    return results


@friendsRouter.get("/friends/requests", response_model=list[FriendshipRead])
def listFriendRequests(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[FriendshipRead]:
    pending = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.addresseeId == user.id,
            FriendshipModel.status == FriendshipStatus.pending,
        )
    ).all()

    results: list[FriendshipRead] = []
    for f in pending:
        read = FriendshipRead.model_validate(f)
        read.friendId = f.requesterId
        requester = session.get(UserModel, f.requesterId)
        if requester:
            read.friendFirstName = requester.firstName
            read.friendLastName = requester.lastName
            read.friendPhotoUrl = requester.photoUrl
        results.append(read)
    return results


@friendsRouter.get("/friends/sent", response_model=list[FriendshipRead])
def listSentFriendRequests(
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> list[FriendshipRead]:
    """Outgoing friend requests still pending acceptance."""
    pending = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.requesterId == user.id,
            FriendshipModel.status == FriendshipStatus.pending,
        )
    ).all()

    results: list[FriendshipRead] = []
    for f in pending:
        read = FriendshipRead.model_validate(f)
        read.friendId = f.addresseeId
        addressee = session.get(UserModel, f.addresseeId)
        if addressee:
            read.friendFirstName = addressee.firstName
            read.friendLastName = addressee.lastName
            read.friendPhotoUrl = addressee.photoUrl
        results.append(read)
    return results


@friendsRouter.post("/friends/request", response_model=FriendshipRead, status_code=201)
def sendFriendRequest(
    body: FriendRequest,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> FriendshipRead:
    if body.targetUserId == user.id:
        raise BadRequest("Cannot friend yourself")

    target = session.get(UserModel, body.targetUserId)
    if not target:
        raise NotFound("User not found")

    existing = _find_existing_friendship(session, user.id, body.targetUserId)
    if existing:
        raise Conflict("Friendship already exists")

    friendship = FriendshipModel(
        requesterId=user.id,
        addresseeId=body.targetUserId,
        status=FriendshipStatus.pending,
    )
    session.add(friendship)
    commitAndRefresh(session, friendship)

    notifyFriendRequestReceived(session, addresseeId=body.targetUserId, requester=user)
    session.commit()

    read = FriendshipRead.model_validate(friendship)
    read.friendId = body.targetUserId
    read.friendFirstName = target.firstName
    read.friendLastName = target.lastName
    read.friendPhotoUrl = target.photoUrl
    return read


@friendsRouter.post("/friends/{friendshipId}/accept", response_model=FriendshipRead)
def acceptFriendRequest(
    friendshipId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> FriendshipRead:
    friendship = session.get(FriendshipModel, friendshipId)
    if not friendship:
        raise NotFound("Friend request not found")
    if friendship.addresseeId != user.id:
        raise Forbidden("Not your request to accept")
    if friendship.status == FriendshipStatus.accepted:
        raise BadRequest("Already accepted")

    friendship.status = FriendshipStatus.accepted
    session.add(friendship)
    commitAndRefresh(session, friendship)

    notifyFriendRequestAccepted(session, requesterId=friendship.requesterId, accepter=user)
    session.commit()

    read = FriendshipRead.model_validate(friendship)
    read.friendId = friendship.requesterId
    requester = session.get(UserModel, friendship.requesterId)
    if requester:
        read.friendFirstName = requester.firstName
        read.friendLastName = requester.lastName
        read.friendPhotoUrl = requester.photoUrl
    return read


@friendsRouter.delete("/friends/{friendshipId}", status_code=204)
def removeFriendship(
    friendshipId: UUID,
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> None:
    friendship = session.get(FriendshipModel, friendshipId)
    if not friendship:
        raise NotFound("Friendship not found")
    if friendship.requesterId != user.id and friendship.addresseeId != user.id:
        raise Forbidden("Not your friendship")
    session.delete(friendship)
    session.commit()


@friendsRouter.get("/friends/search", response_model=FriendSearchResult)
def searchFriends(
    q: str = Query(..., min_length=1),
    user: UserModel = Depends(getCurrentUser),
    session: Session = Depends(getSession),
) -> FriendSearchResult:
    """Search for users: friends first, then all Roam users."""
    q_lower = q.lower()

    friend_ids: set[UUID] = set()
    friendships = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.status == FriendshipStatus.accepted,
            or_(
                FriendshipModel.requesterId == user.id,
                FriendshipModel.addresseeId == user.id,
            ),
        )
    ).all()
    for f in friendships:
        friend_ids.add(f.addresseeId if f.requesterId == user.id else f.requesterId)

    friend_matches: list[UserRead] = []
    if friend_ids:
        friends = session.exec(
            select(UserModel).where(
                col(UserModel.id).in_(friend_ids),
                or_(
                    col(UserModel.firstName).ilike(f"%{q_lower}%"),
                    col(UserModel.lastName).ilike(f"%{q_lower}%"),
                    col(UserModel.username).ilike(f"%{q_lower}%"),
                ),
            ).limit(10)
        ).all()
        friend_matches = [UserRead.model_validate(f) for f in friends]

    others = session.exec(
        select(UserModel).where(
            UserModel.id != user.id,
            ~col(UserModel.id).in_(friend_ids) if friend_ids else UserModel.id != user.id,
            or_(
                col(UserModel.firstName).ilike(f"%{q_lower}%"),
                col(UserModel.lastName).ilike(f"%{q_lower}%"),
                col(UserModel.username).ilike(f"%{q_lower}%"),
            ),
        ).limit(10)
    ).all()
    other_matches = [UserRead.model_validate(u) for u in others]

    return FriendSearchResult(friends=friend_matches, others=other_matches)


def _find_existing_friendship(
    session: Session, user_a: UUID, user_b: UUID
) -> FriendshipModel | None:
    return session.exec(
        select(FriendshipModel).where(
            or_(
                (FriendshipModel.requesterId == user_a)
                & (FriendshipModel.addresseeId == user_b),
                (FriendshipModel.requesterId == user_b)
                & (FriendshipModel.addresseeId == user_a),
            )
        )
    ).first()
