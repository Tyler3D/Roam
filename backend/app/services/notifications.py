"""High-level notification triggers: coincidence match, same reel, trending, proximity."""

import logging
from datetime import datetime, timedelta
from uuid import UUID

from sqlmodel import Session, col, or_, select

from app.models.coincidenceNotificationsSent import CoincidenceNotificationSentModel
from app.models.friendships import FriendshipModel, FriendshipStatus
from app.models.ideas import IdeaModel
from app.models.notifications import NotificationType
from app.models.places import PlaceModel
from app.models.savedReels import SavedReelModel
from app.models.trendingNotificationsSent import TrendingNotificationSentModel
from app.models.users import UserModel
from app.services.push import sendPushToUser

logger = logging.getLogger("roam.notifications")

TRENDING_THRESHOLD = 3
TRENDING_WINDOW_DAYS = 30
PROXIMITY_RADIUS_DEGREES = 0.008


def acceptedFriendIds(session: Session, userId: UUID) -> set[UUID]:
    rows = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.status == FriendshipStatus.accepted,
            or_(
                FriendshipModel.requesterId == userId,
                FriendshipModel.addresseeId == userId,
            ),
        )
    ).all()
    return {
        f.addresseeId if f.requesterId == userId else f.requesterId
        for f in rows
    }


def checkCoincidenceMatch(
    session: Session,
    *,
    idea: IdeaModel,
    user: UserModel,
    friendIds: set[UUID] | None = None,
) -> None:
    """When a new idea is created, check if any friends have ideas at the same place."""
    if not idea.placeId:
        return

    if friendIds is None:
        friendIds = acceptedFriendIds(session, user.id)
    if not friendIds:
        return

    friendIdeas = session.exec(
        select(IdeaModel).where(
            IdeaModel.placeId == idea.placeId,
            col(IdeaModel.userId).in_(friendIds),
        )
    ).all()

    if not friendIdeas:
        return

    place = session.get(PlaceModel, idea.placeId)
    placeName = place.name if place else "a place"

    matchedFriendIds = {fi.userId for fi in friendIdeas}
    allUserIds = matchedFriendIds | {user.id}

    # Batch dedup check — single query instead of per-user SELECT
    alreadySent = set(
        session.exec(
            select(CoincidenceNotificationSentModel.userId).where(
                col(CoincidenceNotificationSentModel.userId).in_(allUserIds),
                CoincidenceNotificationSentModel.placeId == idea.placeId,
            )
        ).all()
    )

    # Batch-load friend users to avoid N+1
    friendUsers = session.exec(
        select(UserModel).where(col(UserModel.id).in_(matchedFriendIds))
    ).all()
    friendUserMap = {u.id: u for u in friendUsers}

    # Build map of friendId -> their idea at this place (for deep linking)
    friendIdeaMap: dict[UUID, UUID] = {}
    for fi in friendIdeas:
        if fi.userId not in friendIdeaMap:
            friendIdeaMap[fi.userId] = fi.id

    # Notify the triggering user once (pick first matched friend for copy)
    if user.id not in alreadySent:
        firstFriend = friendUserMap.get(next(iter(matchedFriendIds)))
        firstName = firstFriend.firstName if firstFriend else "a friend"
        sendPushToUser(
            session,
            userId=user.id,
            notificationType=NotificationType.coincidence_match,
            title=f"You and {firstName} both saved {placeName}",
            body="You should check it out",
            placeId=idea.placeId,
            ideaId=idea.id,
            actorUserId=next(iter(matchedFriendIds)),
        )
        session.add(CoincidenceNotificationSentModel(userId=user.id, placeId=idea.placeId))

    # Notify each matched friend (if not already notified for this place)
    for friendUserId in matchedFriendIds:
        if friendUserId in alreadySent:
            continue
        sendPushToUser(
            session,
            userId=friendUserId,
            notificationType=NotificationType.coincidence_match,
            title=f"You and {user.firstName or 'a friend'} both saved {placeName}",
            body="You should check it out",
            placeId=idea.placeId,
            ideaId=friendIdeaMap.get(friendUserId),
            actorUserId=user.id,
        )
        session.add(CoincidenceNotificationSentModel(userId=friendUserId, placeId=idea.placeId))


def checkSameReelSaved(
    session: Session,
    *,
    savedReel: SavedReelModel,
    user: UserModel,
    friendIds: set[UUID] | None = None,
) -> None:
    """When a reel is saved, check if any friends saved the same reel URL."""
    if not savedReel.reelUrl:
        return

    if friendIds is None:
        friendIds = acceptedFriendIds(session, user.id)
    if not friendIds:
        return

    friendReels = session.exec(
        select(SavedReelModel).where(
            SavedReelModel.reelUrl == savedReel.reelUrl,
            col(SavedReelModel.userId).in_(friendIds),
            SavedReelModel.id != savedReel.id,
        )
    ).all()

    if not friendReels:
        return

    # Batch-load friend users to avoid N+1
    matchedFriendIds = {fr.userId for fr in friendReels}
    friendUsers = session.exec(
        select(UserModel).where(col(UserModel.id).in_(matchedFriendIds))
    ).all()
    friendUserMap = {u.id: u for u in friendUsers}

    # Send ONE notification to the triggering user (not one per friend)
    firstFriend = friendUserMap.get(next(iter(matchedFriendIds)))
    firstName = firstFriend.firstName if firstFriend else "Someone"
    if len(matchedFriendIds) == 1:
        userTitle = f"You and {firstName} saved the same reel"
    else:
        userTitle = f"You and {len(matchedFriendIds)} friends saved the same reel"

    sendPushToUser(
        session,
        userId=user.id,
        notificationType=NotificationType.same_reel_saved,
        title=userTitle,
        body="You both saw this one",
        savedReelId=savedReel.id,
        actorUserId=next(iter(matchedFriendIds)),
    )

    # Notify each friend (deduplicated by userId within this batch)
    notifiedUserIds: set[UUID] = set()
    for fr in friendReels:
        if fr.userId in notifiedUserIds:
            continue
        notifiedUserIds.add(fr.userId)

        sendPushToUser(
            session,
            userId=fr.userId,
            notificationType=NotificationType.same_reel_saved,
            title=f"You and {user.firstName or 'a friend'} saved the same reel",
            body="You both saw this one",
            savedReelId=fr.id,
            actorUserId=user.id,
        )


def checkTrendingPlace(
    session: Session,
    *,
    placeId: UUID,
    triggeringUserId: UUID,
    friendIds: set[UUID] | None = None,
) -> None:
    """Check if a place has crossed the trending threshold among friends."""
    if friendIds is None:
        friendIds = acceptedFriendIds(session, triggeringUserId)
    if not friendIds:
        return

    cutoff = datetime.utcnow() - timedelta(days=TRENDING_WINDOW_DAYS)
    allRelevantUsers = friendIds | {triggeringUserId}

    ideasAtPlace = session.exec(
        select(IdeaModel.userId).where(
            IdeaModel.placeId == placeId,
            col(IdeaModel.userId).in_(allRelevantUsers),
            IdeaModel.createdAt >= cutoff,
        )
    ).all()

    uniqueSavers = set(ideasAtPlace)
    if len(uniqueSavers) < TRENDING_THRESHOLD:
        return

    place = session.get(PlaceModel, placeId)
    placeName = place.name if place else "a place"
    saverCount = len(uniqueSavers)

    # Batch dedup check — single query instead of per-user SELECT
    alreadySent = set(
        session.exec(
            select(TrendingNotificationSentModel.userId).where(
                col(TrendingNotificationSentModel.userId).in_(uniqueSavers),
                TrendingNotificationSentModel.placeId == placeId,
            )
        ).all()
    )

    # Batch insert dedup rows + send pushes only for new recipients
    for uid in uniqueSavers:
        if uid in alreadySent:
            continue

        session.add(TrendingNotificationSentModel(userId=uid, placeId=placeId))

        friendCount = saverCount - 1
        sendPushToUser(
            session,
            userId=uid,
            notificationType=NotificationType.trending_place,
            title=f"{placeName} is popular in your circle",
            body=f"{friendCount} of your friends saved this place",
            placeId=placeId,
        )


def notifyCollectionIdeaAdded(
    session: Session,
    *,
    collectionId: UUID,
    ideaId: UUID,
    placeName: str | None,
    adderUserId: UUID,
    adderFirstName: str,
    collectionName: str,
    memberUserIds: list[UUID],
) -> None:
    """Notify all collection members (except the adder) when an idea is added."""
    displayPlace = placeName or "a new spot"
    for uid in memberUserIds:
        if uid == adderUserId:
            continue
        sendPushToUser(
            session,
            userId=uid,
            notificationType=NotificationType.collection_idea_added,
            title=f"{adderFirstName or 'Someone'} added {displayPlace} to {collectionName}",
            collectionId=collectionId,
            ideaId=ideaId,
            actorUserId=adderUserId,
        )


def notifyReelProcessed(
    session: Session,
    *,
    userId: UUID,
    savedReelId: UUID,
    status: str,
    ideaId: UUID | None = None,
    placeName: str | None = None,
    candidateCount: int = 0,
) -> None:
    """Notify user when their reel finishes processing."""
    if status == "promoted":
        title = "See your new idea on Roam"
        body = f"{placeName} is on your map" if placeName else "Your idea is on the map"
        ntype = NotificationType.reel_processed
    elif status == "needs_review":
        placesWord = "place" if candidateCount == 1 else "places"
        title = f"Your reel found {candidateCount} {placesWord}"
        body = "Pick the ones you want to save"
        ntype = NotificationType.reel_needs_review
    else:
        return

    sendPushToUser(
        session,
        userId=userId,
        notificationType=ntype,
        title=title,
        body=body,
        savedReelId=savedReelId,
        ideaId=ideaId,
    )


def notifyFriendRequestReceived(
    session: Session,
    *,
    addresseeId: UUID,
    requester: UserModel,
) -> None:
    """Notify user when they receive a friend request."""
    sendPushToUser(
        session,
        userId=addresseeId,
        notificationType=NotificationType.friend_request,
        title=f"{requester.firstName or 'Someone'} wants to be friends on Roam",
        actorUserId=requester.id,
    )


def notifyFriendRequestAccepted(
    session: Session,
    *,
    requesterId: UUID,
    accepter: UserModel,
) -> None:
    """Notify the requester when their friend request is accepted."""
    sendPushToUser(
        session,
        userId=requesterId,
        notificationType=NotificationType.friend_request_accepted,
        title=f"{accepter.firstName or 'Someone'} accepted your friend request",
        actorUserId=accepter.id,
    )


def checkProximitySave(
    session: Session,
    *,
    idea: IdeaModel,
    user: UserModel,
    userLatitude: float | None = None,
    userLongitude: float | None = None,
) -> None:
    """Placeholder — requires client-side location tracking to be useful."""
    pass
