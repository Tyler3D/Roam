# Notifications

Roam uses a **push-first** notification system. There is no in-app inbox or notification center -- every notification is a native iOS push delivered via Firebase Cloud Messaging (FCM). Notifications are split into two tiers based on urgency, with volume guardrails to prevent spam.

## Design philosophy

- **Ambient awareness over social pressure.** Notifications should make the app feel like a living map, not a social feed demanding attention.
- **Saves as social signals.** When a friend saves a place you also saved, or multiple friends cluster around the same spot, that's meaningful signal worth surfacing.
- **Push-only, no inbox.** Different notification types fire at different frequencies (real-time, weekly, monthly) with deduplication to avoid noise.

---

## Tier 1: Real-time push notifications

These fire immediately when the triggering event occurs.

### Reel processed

- **What the user sees:** "See your new idea on Roam" (auto-promoted) or "Your reel found 2 places" (needs review)
- **When it fires:** After the reel ingestion pipeline finishes processing a shared reel. Auto-promoted reels get a confirmation push; multi-candidate reels prompt the user to review.
- **Tap action:** Opens the reel in the Reels tab.

### Collection activity

- **What the user sees:** "[Tyler] added Blue Bottle to Weekend spots"
- **When it fires:** When any member adds an idea to a shared collection. The adder does not get notified -- only other members.
- **Tap action:** Opens the collection.

### Coincidence match

- **What the user sees:** "You and [Tyler] both saved Blue Bottle"
- **When it fires:** When a user creates or promotes an idea at a place where a friend already has an idea. Both the user and the friend are notified.
- **Dedup:** One notification per user per place, ever. If you already got a coincidence notification for Blue Bottle, a second friend saving it won't trigger another one. The `coincidence_notifications_sent` table enforces this with a `UNIQUE(userId, placeId)` constraint.

### Same reel saved

- **What the user sees:** "You and [Tyler] saved the same reel" (or "You and 3 friends saved the same reel")
- **When it fires:** When a user's reel finishes processing and the same reel URL was also saved by one or more friends.
- **Volume control:** The triggering user gets one aggregated notification regardless of how many friends matched. Each friend gets one individual notification.

### Trending among friends

- **What the user sees:** "[Place name] is popular in your circle -- 3 of your friends saved this place"
- **When it fires:** When 3 or more users in a friend group (including the triggering user) have saved ideas at the same place within the last 30 days.
- **Dedup:** One-shot per user per place, ever. Once you've been told a place is trending, you won't be told again even if more friends save it. The `trending_notifications_sent` table enforces this.

### Friend request received

- **What the user sees:** "[Tyler] wants to be friends on Roam"
- **When it fires:** When another user sends a friend request.

### Friend request accepted

- **What the user sees:** "[Tyler] accepted your friend request"
- **When it fires:** When the addressee accepts a pending friend request. Only the original requester is notified.

### Proximity save (stubbed)

Not yet active. Will fire when a friend saves a place near the user's current location. Requires client-side location tracking infrastructure that doesn't exist yet.

---

## Tier 2: Digest notifications

These are batched summaries sent on a schedule by a background thread inside the server process. No external cron or scheduler is needed.

### Weekly friend activity digest

- **What the user sees:** "This week on Roam" with a body like "Tyler saved 4 spots, Sarah saved 2 spots. You have 3 reels waiting for review"
- **When it fires:** Once per week for every active user who has friends with recent activity or unreviewed reels.
- **Content:** Summarizes the top 3 most active friends by save count, plus a count of reels in `needs_review` status.

### Monthly personal stats

- **What the user sees:** "Your month on Roam -- You saved 12 ideas this month across 4 neighborhoods"
- **When it fires:** Once per month for every active user who saved at least one idea in the past 30 days.
- **Content:** Total idea count and count of distinct cities/neighborhoods.

---

## Future ideas

Aspirational notification concepts that aren't implemented yet are documented in [FUTURE_NOTIFICATION_IDEAS.md](FUTURE_NOTIFICATION_IDEAS.md).

---

## Technical details

### Architecture

All notifications are **push-only** via Firebase Cloud Messaging (FCM). The system has three layers:

1. **Notification triggers** (`backend/app/services/notifications.py`) -- Business logic that decides when and who to notify. Called from API routes and services (reel ingestion, reel promotion, friend requests, collection linking).
2. **Push dispatch** (`backend/app/services/push.py`) -- Creates a `NotificationModel` row in the database, then dispatches the FCM HTTP call to a background thread pool.
3. **Digest scheduler** (`backend/app/services/digest.py`) -- A daemon thread started at FastAPI boot that fires weekly and monthly digests on a timer.

### Push dispatch flow

```
API request (e.g., promote reel)
  → notification trigger (e.g., checkCoincidenceMatch)
    → sendPushToUser()
      → INSERT notification row (synchronous, flushed to DB)
      → submit FCM call to ThreadPoolExecutor (background, non-blocking)
        → background thread gets its own DB session
        → looks up device_tokens for userId
        → calls FCM for each token
        → deletes stale (unregistered) tokens
```

The notification row is always persisted, even if FCM delivery fails. FCM calls never block API responses.

### Device token management

Users can have multiple device tokens (multiple devices, token rotation). Tokens are managed via two API endpoints:

- `POST /api/device-tokens` -- Register or update an FCM token (called by the iOS app on launch after `FirebaseMessaging` provides a token).
- `DELETE /api/device-tokens` -- Unregister a token (called on sign-out).

Stale tokens (where FCM returns `UnregisteredError`) are automatically cleaned up during push dispatch.

### Deduplication tables

Two dedicated tables prevent repeat notifications for the same event:

| Table | Unique constraint | Purpose |
|-------|-------------------|---------|
| `trending_notifications_sent` | `(userId, placeId)` | A user only gets one "trending" push per place, ever |
| `coincidence_notifications_sent` | `(userId, placeId)` | A user only gets one "coincidence" push per place, ever |

Both are checked with batch `IN()` queries to avoid N+1 patterns when multiple users are involved.

### Digest scheduler

The digest runs as a daemon thread inside the FastAPI process, started via `startScheduler()` in the `startup` event and stopped via `stopScheduler()` in `shutdown`. The thread wakes every 60 seconds and checks elapsed time against `WEEKLY_INTERVAL_SECONDS` (7 days) and `MONTHLY_INTERVAL_SECONDS` (30 days).

Each digest run gets its own DB session and batch-loads all data upfront (friendships, recent ideas, review counts, places, user names) to avoid per-user query loops.

### N+1 prevention

All notification functions accept an optional `friendIds` parameter. When multiple checks run in sequence (e.g., after reel ingestion: coincidence + trending + same-reel), the caller computes `acceptedFriendIds()` once and passes it to each function. Within each function, related models (users, places) are batch-loaded with `IN()` queries.

### Notification types in the database

| `notificationType` enum value | Triggered by | Tier |
|-------------------------------|-------------|------|
| `reel_processed` | Reel ingestion completes (auto-promoted) | Real-time |
| `reel_needs_review` | Reel ingestion completes (multi-candidate) | Real-time |
| `collection_idea_added` | Idea linked to a shared collection | Real-time |
| `coincidence_match` | New idea at a place a friend also saved | Real-time |
| `same_reel_saved` | Same reel URL shared by friends | Real-time |
| `trending_place` | 3+ friends save ideas at the same place within 30 days | Real-time |
| `friend_request` | Friend request received | Real-time |
| `friend_request_accepted` | Friend request accepted | Real-time |
| `proximity_save` | (Stubbed) Friend saves near user's location | Real-time |
| `weekly_digest` | Background scheduler, every 7 days | Digest |
| `monthly_stats` | Background scheduler, every 30 days | Digest |

### Deep linking

Every push notification carries a data payload with the notification `type` and relevant entity IDs (`placeId`, `ideaId`, `collectionId`, `savedReelId`, `planId`, `actorUserId`). The iOS app uses this payload to route the user to the correct screen when they tap the notification.

### Key files

| File | Role |
|------|------|
| `backend/app/services/push.py` | FCM dispatch, thread pool, deep-link data |
| `backend/app/services/notifications.py` | All real-time notification triggers |
| `backend/app/services/digest.py` | Weekly/monthly digest logic + background scheduler |
| `backend/app/models/notifications.py` | `NotificationModel`, `NotificationType` enum |
| `backend/app/models/deviceTokens.py` | `DeviceTokenModel` |
| `backend/app/models/trendingNotificationsSent.py` | Trending dedup model |
| `backend/app/models/coincidenceNotificationsSent.py` | Coincidence dedup model |
| `backend/app/api/deviceTokens.py` | Token registration/unregistration endpoints |
| `Roam/AppDelegate.swift` | iOS push registration, FCM setup, notification handling |
| `Roam/Services/PushNotificationManager.swift` | iOS FCM token lifecycle |
| `Roam/Services/APIClient.swift` | `registerDeviceToken` / `unregisterDeviceToken` |
