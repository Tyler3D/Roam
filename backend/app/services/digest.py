"""Weekly and monthly digest push notifications.

Runs automatically inside the FastAPI process via a background scheduler thread
started at app startup. No cron or external process needed.
"""

import logging
import threading
import time
from datetime import datetime, timedelta
from uuid import UUID

from sqlmodel import Session, col, func, or_, select

from app.common.db import getSession
from app.models.friendships import FriendshipModel, FriendshipStatus
from app.models.ideas import IdeaModel
from app.models.notifications import NotificationType
from app.models.places import PlaceModel
from app.models.savedReels import SavedReelModel, SavedReelStatus
from app.models.users import UserModel
from app.services.push import sendPushToUser

logger = logging.getLogger("roam.digest")

WEEKLY_INTERVAL_SECONDS = 7 * 24 * 60 * 60
MONTHLY_INTERVAL_SECONDS = 30 * 24 * 60 * 60

_schedulerStarted = False


def sendWeeklyDigests(session: Session) -> int:
    """Send a weekly digest push to every active user with friend activity."""
    cutoff = datetime.utcnow() - timedelta(days=7)
    users = session.exec(select(UserModel).where(UserModel.isActive == True)).all()  # noqa: E712
    if not users:
        return 0

    userIds = [u.id for u in users]

    # Batch-load all friendships for active users in one query
    allFriendships = session.exec(
        select(FriendshipModel).where(
            FriendshipModel.status == FriendshipStatus.accepted,
            or_(
                col(FriendshipModel.requesterId).in_(userIds),
                col(FriendshipModel.addresseeId).in_(userIds),
            ),
        )
    ).all()

    friendMap: dict[UUID, set[UUID]] = {uid: set() for uid in userIds}
    for f in allFriendships:
        if f.requesterId in friendMap:
            friendMap[f.requesterId].add(f.addresseeId)
        if f.addresseeId in friendMap:
            friendMap[f.addresseeId].add(f.requesterId)

    # Collect all friend IDs across all users for a single ideas query
    allFriendIds: set[UUID] = set()
    for fids in friendMap.values():
        allFriendIds |= fids

    # Batch-load recent friend ideas
    recentFriendIdeas: list[IdeaModel] = []
    if allFriendIds:
        recentFriendIdeas = list(
            session.exec(
                select(IdeaModel).where(
                    col(IdeaModel.userId).in_(allFriendIds),
                    IdeaModel.createdAt >= cutoff,
                )
            ).all()
        )

    # Index ideas by userId for fast lookup
    ideasByUser: dict[UUID, list[IdeaModel]] = {}
    for idea in recentFriendIdeas:
        ideasByUser.setdefault(idea.userId, []).append(idea)

    # Batch-load needs_review counts per user
    reviewRows = session.exec(
        select(SavedReelModel.userId, func.count(SavedReelModel.id)).where(
            col(SavedReelModel.userId).in_(userIds),
            SavedReelModel.status == SavedReelStatus.needs_review,
        ).group_by(SavedReelModel.userId)
    ).all()
    reviewCountMap: dict[UUID, int] = {uid: cnt for uid, cnt in reviewRows}

    # Batch-load all friend user names for display
    allFriendUserIds = {idea.userId for idea in recentFriendIdeas}
    friendUserMap: dict[UUID, UserModel] = {}
    if allFriendUserIds:
        friendUsers = session.exec(
            select(UserModel).where(col(UserModel.id).in_(allFriendUserIds))
        ).all()
        friendUserMap = {u.id: u for u in friendUsers}

    sentCount = 0
    for user in users:
        myFriendIds = friendMap.get(user.id, set())
        if not myFriendIds:
            continue

        myFriendIdeas = [i for fid in myFriendIds for i in ideasByUser.get(fid, [])]
        needsReviewCount = reviewCountMap.get(user.id, 0)

        if not myFriendIdeas and not needsReviewCount:
            continue

        savesByFriend: dict[str, int] = {}
        for fi in myFriendIdeas:
            fUser = friendUserMap.get(fi.userId)
            name = fUser.firstName if fUser else "Someone"
            savesByFriend[name] = savesByFriend.get(name, 0) + 1

        parts: list[str] = []
        for name, count in sorted(savesByFriend.items(), key=lambda x: -x[1])[:3]:
            spots = "spot" if count == 1 else "spots"
            parts.append(f"{name} saved {count} {spots}")

        body = ", ".join(parts) if parts else ""
        if needsReviewCount:
            reelsWord = "reel" if needsReviewCount == 1 else "reels"
            reviewNote = f"You have {needsReviewCount} {reelsWord} waiting for review"
            body = f"{body}. {reviewNote}" if body else reviewNote

        sendPushToUser(
            session,
            userId=user.id,
            notificationType=NotificationType.weekly_digest,
            title="This week on Roam",
            body=body[:500] if body else None,
        )
        sentCount += 1

    session.commit()
    return sentCount


def sendMonthlyStats(session: Session) -> int:
    """Send monthly personal stats push to every active user."""
    cutoff = datetime.utcnow() - timedelta(days=30)
    users = session.exec(select(UserModel).where(UserModel.isActive == True)).all()  # noqa: E712
    if not users:
        return 0

    userIds = [u.id for u in users]

    # Batch-load recent ideas for all users
    allRecentIdeas = list(
        session.exec(
            select(IdeaModel).where(
                col(IdeaModel.userId).in_(userIds),
                IdeaModel.createdAt >= cutoff,
            )
        ).all()
    )

    ideasByUser: dict[UUID, list[IdeaModel]] = {}
    for idea in allRecentIdeas:
        ideasByUser.setdefault(idea.userId, []).append(idea)

    # Batch-load all referenced places
    allPlaceIds: set[UUID] = set()
    for idea in allRecentIdeas:
        if idea.placeId:
            allPlaceIds.add(idea.placeId)

    placeMap: dict[UUID, PlaceModel] = {}
    if allPlaceIds:
        places = session.exec(
            select(PlaceModel).where(col(PlaceModel.id).in_(allPlaceIds))
        ).all()
        placeMap = {p.id: p for p in places}

    sentCount = 0
    for user in users:
        ideas = ideasByUser.get(user.id, [])
        if not ideas:
            continue

        ideaCount = len(ideas)
        neighborhoods: set[str] = set()
        for i in ideas:
            if i.placeId:
                p = placeMap.get(i.placeId)
                if p and p.city:
                    neighborhoods.add(p.city)

        neighborhoodCount = len(neighborhoods)
        nWord = "neighborhood" if neighborhoodCount == 1 else "neighborhoods"
        body = f"You saved {ideaCount} ideas this month"
        if neighborhoodCount:
            body += f" across {neighborhoodCount} {nWord}"

        sendPushToUser(
            session,
            userId=user.id,
            notificationType=NotificationType.monthly_stats,
            title="Your month on Roam",
            body=body,
        )
        sentCount += 1

    session.commit()
    return sentCount


def _runWithSession(fn, label: str) -> None:
    """Run a digest function with its own DB session, logging any errors."""
    sessionGen = getSession()
    session = next(sessionGen)
    try:
        count = fn(session)
        logger.info(f"{label}_sent", extra={"count": count})
    except Exception:
        logger.exception(f"{label}_failed")
    finally:
        try:
            next(sessionGen, None)
        except StopIteration:
            pass


def _schedulerLoop(stopEvent: threading.Event) -> None:
    """Background loop that fires weekly/monthly digests on schedule."""
    lastWeekly = datetime.utcnow()
    lastMonthly = datetime.utcnow()

    while not stopEvent.is_set():
        stopEvent.wait(60)
        if stopEvent.is_set():
            break

        now = datetime.utcnow()

        if (now - lastWeekly).total_seconds() >= WEEKLY_INTERVAL_SECONDS:
            logger.info("digest_scheduler_firing_weekly")
            _runWithSession(sendWeeklyDigests, "weekly_digest")
            lastWeekly = now

        if (now - lastMonthly).total_seconds() >= MONTHLY_INTERVAL_SECONDS:
            logger.info("digest_scheduler_firing_monthly")
            _runWithSession(sendMonthlyStats, "monthly_stats")
            lastMonthly = now


_stopEvent = threading.Event()


def startScheduler() -> None:
    """Start the background digest scheduler. Safe to call multiple times."""
    global _schedulerStarted
    if _schedulerStarted:
        return
    _schedulerStarted = True
    _stopEvent.clear()
    t = threading.Thread(target=_schedulerLoop, args=(_stopEvent,), daemon=True)
    t.start()
    logger.info("digest_scheduler_started")


def stopScheduler() -> None:
    """Signal the background scheduler to stop."""
    _stopEvent.set()
