## Project Goals
Build a multi-user date-idea app with Firebase Auth and a Postgres-backed FastAPI
backend, including an automated reel ingestion pipeline. Users can create, share,
and collaboratively edit date ideas and the ML-extracted metadata (suggested tags
and classifications). The system should support location-aware ideas for map
display and allow organizing and filtering by both user tags and ML-suggested
tags.

## Product Requirements
- Multi-user accounts with Firebase Auth.
- Date ideas (pins) with location, status, tags, and metadata.
- Sharing with individual users by username (no groups in MVP).
- Shared pins are editable by collaborators.
- ML-extracted fields are editable by users and treated as suggestions.
- Reels ingestion from a bot account, with automated classification + location.
- Search, filter, and sort by tags, status, and ML-suggested fields.
- No fixed "type" field; tags + ML fields cover classification.

## Technical Specs

### Auth
- Firebase Authentication on frontend.
- Backend verifies Firebase ID token on each request.
- Backend creates/updates local user record on first login.

### API (FastAPI)
All endpoints require `Authorization: Bearer <firebaseIdToken>` unless noted.

#### Users
- `GET /me`
  - Returns current user profile.
- `POST /me`
  - Creates/ensures a user record from Firebase claims.
- `GET /users/search?username=...`
  - Finds users by username for sharing.

#### Pins
- `GET /pins`
  - Query params: `search`, `status`, `tag`, `mlTag`, `sort`,
    `shared` (bool; default true), `owner` (bool; default true)
  - Returns owned + shared pins.
- `POST /pins`
  - Creates a new pin (manual or ingest).
- `GET /pins/{id}`
  - Returns a pin if user has access.
- `PATCH /pins/{id}`
  - Updates pin fields and ML extraction fields (suggested values).
- `DELETE /pins/{id}`
  - Deletes a pin (owner only).
  - Use `PATCH /pins/{id}` to update `lastViewedAt`.

#### Sharing
- `POST /pins/{id}/share`
  - Body: `{ "username": "string", "role": "collaborator|viewer" }`
  - Adds access for a user (upsert to enforce a single role).
- `GET /pins/{id}/shares`
  - Lists share entries.
- `DELETE /pins/{id}/shares/{shareId}`
  - Removes access.

#### Ingestion / ML
- `POST /ingest/reel`
  - Internal endpoint used by webhook or worker.
  - Body includes reelUrl, platform, senderUserId, rawPayload.
- `POST /ml/classify`
  - Body: `{ text, url, metadata }`
  - Returns suggested fields and location candidates.
- `GET /ingest/jobs`
  - Debug/admin listing of ingestion jobs.

### Schema (Postgres)

#### users
- `id` uuid pk
- `firebaseUid` text unique
- `username` text unique
- `email` text unique
- `displayName` text
- `photoUrl` text
- `createdAt` timestamptz

#### datePins
- `id` uuid pk
- `ownerId` uuid fk -> users.id
- `title` text
- `notes` text
- `link` text
- `status` enum: saved | planned | done
- `tags` text[]
- `locationName` text
- `locationLat` double
- `locationLng` double
- `createdAt` timestamptz
- `updatedAt` timestamptz
- `lastViewedAt` timestamptz
- `source` enum: manual | reelIngest
- `sourceRef` text

#### pinShares
- `id` uuid pk
- `pinId` uuid fk -> datePins.id
- `userId` uuid fk -> users.id
- `role` enum: collaborator | viewer
- `createdAt` timestamptz
- Unique constraint: `(pinId, userId)` to allow only one role per user per pin.

#### mlExtractions
Stores suggested values that are user-editable and optional.
- `id` uuid pk
- `pinId` uuid fk -> datePins.id
- `activityType` enum: dinner | walk | DIY | trip | event | cozyNight | chaoticNight
- `effortLevel` enum: lowEffort | planned | saturday
- `context` enum: date | friends | solo | travel
- `constraints` jsonb
  - example keys: indoorOutdoor, weatherDependent, timeOfDay
- `locationSuggestion` jsonb
  - example keys: name, lat, lng, confidence
- `suggestedTags` text[]
- `confidence` jsonb
- `rawModelOutput` jsonb
- `createdAt` timestamptz
- `updatedAt` timestamptz

#### reelIngestJobs
- `id` uuid pk
- `platform` enum: tiktok | instagram
- `senderUserId` uuid fk -> users.id
- `reelUrl` text
- `rawPayload` jsonb
- `status` enum: queued | processing | done | failed
- `error` text
- `createdAt` timestamptz
- `updatedAt` timestamptz

### Access Control
- A user can read a pin if:
  - `ownerId == user.id` OR
  - a `pinShares` record exists for user
- A user can edit a pin if:
  - `ownerId == user.id` OR
  - `pinShares.role == collaborator`
- Only owner can delete.

## ML Pipeline

### Inputs
- Reel URL, caption, hashtags, audio transcript (if available),
  location tags, and extracted text.

### Steps
1. Ingest message from bot account webhook.
2. Resolve reel media and metadata.
3. Run LLM classification for:
   - Activity type (dinner, walk, DIY, trip, event, cozy night, chaotic night)
   - Effort level (low effort, planned, "this takes a Saturday")
   - Context (date, friends, solo, travel)
   - Constraints (indoor/outdoor, weather-dependent, time-of-day)
4. Infer or geocode location (places API).
5. Persist:
   - Create `datePins` row.
   - Store ML suggestions in `mlExtractions`.
6. Share with sender and any default collaborator.

### Model Output Schema (suggested)
{
  "title": "string",
  "summary": "string",
  "activityType": "dinner|walk|DIY|trip|event|cozyNight|chaoticNight",
  "effortLevel": "lowEffort|planned|saturday",
  "context": "date|friends|solo|travel",
  "constraints": {
    "indoorOutdoor": "indoor|outdoor|either",
    "weatherDependent": true,
    "timeOfDay": "morning|afternoon|evening|night|any"
  },
  "location": {
    "name": "string",
    "lat": 0,
    "lng": 0,
    "confidence": 0.0
  },
  "suggestedTags": ["string"]
}

