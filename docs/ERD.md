# Entity Relationship Diagram

Reflects `sql/schema.sql` (including `pipeline_results.promptVersion` and `user_oauth_tokens`).

```mermaid
erDiagram
    users {
        uuid id PK
        text firebaseUid UK "nullable"
        text username UK "nullable"
        text email UK "nullable"
        text firstName
        text lastName
        text phone
        text photoUrl
        text city
        jsonb interestTags
        boolean isActive
        boolean isOnboarded
        boolean isGuestUser
        boolean emailVerified
        timestamptz createdAt
    }

    places {
        uuid id PK
        text googlePlaceId UK "nullable"
        text name
        text address
        text city
        double latitude
        double longitude
        text category
        jsonb openingHours
        text placeTypes "postgres text[]"
        timestamptz createdAt
    }

    pipeline_results {
        uuid id PK
        uuid ideaId FK "nullable"
        uuid jobId FK "nullable"
        text source
        text refinedTitle
        text category
        integer estimatedMinutes
        text promptVersion "nullable"
        text modelName
        jsonb rawOutput
        timestamptz createdAt
    }

    place_suggestions {
        uuid id PK
        uuid resultId FK
        uuid placeId FK "nullable"
        text rawName
        double confidence
        boolean isSelected
        timestamptz createdAt
    }

    friendships {
        uuid id PK
        uuid requesterId FK
        uuid addresseeId FK
        friendshipStatus status
        timestamptz createdAt
    }

    ideas {
        uuid id PK
        uuid userId FK
        text title
        text notes
        text sourceUrl
        text displayName "nullable"
        uuid placeId FK "nullable"
        ideaStatus status
        integer planCount "computed via ideas_with_plan_count view"
        timestamptz createdAt
        timestamptz updatedAt
    }

    plans {
        uuid id PK
        uuid creatorId FK
        uuid placeId FK "nullable"
        uuid ideaId FK "nullable"
        text title
        timestamptz scheduledAt
        planStatus status
        text shareCode UK
        text rawPrompt
        integer estimatedMinutes
        text calendarEventId
        integer partySize
        integer rating "1-5"
        text taskNotes
        timestamptz createdAt
        timestamptz updatedAt
    }

    plan_members {
        uuid id PK
        uuid planId FK
        uuid userId FK
        memberRole role
        rsvpStatus rsvpStatus
        text inviteToken
        integer rating "1-5"
        timestamptz invitedAt
        timestamptz respondedAt
    }

    plan_tasks {
        uuid id PK
        uuid planId FK
        uuid assigneeId FK
        text description
        boolean isCompleted
        timestamptz createdAt
        timestamptz completedAt
    }

    plan_messages {
        uuid id PK
        uuid planId FK
        uuid userId FK
        text content
        boolean isSystem
        timestamptz createdAt
    }

    user_oauth_tokens {
        uuid id PK
        uuid userId FK
        text provider
        text encryptedAccessToken
        text encryptedRefreshToken "nullable"
        timestamptz expiresAt "nullable"
        timestamptz createdAt
        timestamptz updatedAt
    }

    notifications {
        uuid id PK
        uuid userId FK
        notificationType type
        uuid planId FK "nullable"
        text title
        text body "nullable"
        boolean isRead
        timestamptz createdAt
    }

    reel_ingestion_jobs {
        uuid id PK
        uuid userId FK
        text reelUrl
        text shareText
        text reelTitle
        text ogDescription
        text ogKeywords
        jobStatus status
        text error
        timestamptz createdAt
        timestamptz updatedAt
    }

    users ||--o{ friendships : "requests"
    users ||--o{ friendships : "receives"
    users ||--o{ ideas : "creates"
    users ||--o{ plans : "creates"
    users ||--o{ plan_members : "joins"
    users ||--o{ plan_messages : "sends"
    users ||--o{ notifications : "receives"
    users ||--o{ reel_ingestion_jobs : "submits"
    users ||--o{ user_oauth_tokens : "stores"

    ideas ||--o{ pipeline_results : "results"
    reel_ingestion_jobs ||--o{ pipeline_results : "produces"
    pipeline_results ||--o{ place_suggestions : "has"

    place_suggestions }o--|| places : "references"

    places ||--o{ ideas : "located at"
    places ||--o{ plans : "hosts"

    ideas ||--o{ plans : "spawns"

    plans ||--o{ plan_members : "has"
    plans ||--o{ plan_tasks : "has"
    plans ||--o{ plan_messages : "contains"
    plans ||--o{ notifications : "triggers"

    plan_members ||--o{ plan_tasks : "assigned"
```

## Enums

| Enum | Values | Used By |
|------|--------|---------|
| `ideaStatus` | `captured`, `suggesting`, `ready`, `planned` (deprecated) | `ideas.status` — ideas stay `ready` after promotion; `planned` never set |
| `jobStatus` | `processing`, `done`, `failed` | `reel_ingestion_jobs.status` |
| `planStatus` | `draft`, `confirmed`, `completed`, `cancelled` | `plans.status` |
| `rsvpStatus` | `pending`, `accepted`, `declined` | `plan_members.rsvpStatus` |
| `memberRole` | `organizer`, `member` | `plan_members.role` |
| `friendshipStatus` | `pending`, `accepted` | `friendships.status` |
| `notificationType` | `invite_received`, `rsvp_accepted`, `rsvp_declined`, `task_assigned`, `plan_reminder`, `rate_prompt`, `friend_request` | `notifications.type` |

## Relationships

| From | To | Type | On Delete |
|------|----|------|-----------|
| `plans.creatorId` | `users.id` | many-to-one | CASCADE |
| `plans.placeId` | `places.id` | many-to-one (nullable) | SET NULL |
| `plans.ideaId` | `ideas.id` | many-to-one (nullable) | SET NULL |
| `ideas.userId` | `users.id` | many-to-one | CASCADE |
| `ideas.placeId` | `places.id` | many-to-one (nullable) | SET NULL |
| `pipeline_results.ideaId` | `ideas.id` | many-to-one (nullable) | CASCADE |
| `pipeline_results.jobId` | `reel_ingestion_jobs.id` | many-to-one (nullable) | SET NULL |
| `place_suggestions.resultId` | `pipeline_results.id` | many-to-one | CASCADE |
| `place_suggestions.placeId` | `places.id` | many-to-one (nullable) | SET NULL |
| `plan_members.planId` | `plans.id` | many-to-one | CASCADE |
| `plan_members.userId` | `users.id` | many-to-one | CASCADE |
| `plan_tasks.planId` | `plans.id` | many-to-one | CASCADE |
| `plan_tasks.assigneeId` | `plan_members.id` | many-to-one | CASCADE |
| `plan_messages.planId` | `plans.id` | many-to-one | CASCADE |
| `plan_messages.userId` | `users.id` | many-to-one | CASCADE |
| `friendships.requesterId` | `users.id` | many-to-one | CASCADE |
| `friendships.addresseeId` | `users.id` | many-to-one | CASCADE |
| `notifications.userId` | `users.id` | many-to-one | CASCADE |
| `notifications.planId` | `plans.id` | many-to-one (nullable) | CASCADE |
| `reel_ingestion_jobs.userId` | `users.id` | many-to-one | CASCADE |
| `user_oauth_tokens.userId` | `users.id` | many-to-one | CASCADE |

### Unique constraints (indexes)

| Table | Constraint |
|-------|------------|
| `user_oauth_tokens` | `UNIQUE ("userId", "provider")` |
| `friendships` | `UNIQUE` on `(LEAST(requesterId, addresseeId), GREATEST(requesterId, addresseeId))` (one row per unordered pair) |
| `reel_ingestion_jobs` | `UNIQUE ("userId", "reelUrl")` |

### Check constraints

| Table | Rule |
|-------|------|
| `pipeline_results` | `reel_result_has_idea`: if `jobId` is set, `ideaId` must be set (`jobId IS NULL OR ideaId IS NOT NULL`) |
| `friendships` | `requesterId <> addresseeId` |
| `plans` / `plan_members` | `rating` in 1–5 when present (see schema `CHECK`) |

## Views

| View | Definition | Purpose |
|------|------------|---------|
| `ideas_with_plan_count` | `ideas` LEFT JOIN `plans` GROUP BY `ideas.id` | Adds computed `planCount` for each idea; used by API when listing ideas |

## Data Flow

```
Reel shared -> reel_ingestion_job -> idea (captured) -> suggesting -> pipeline_result + place_suggestions -> ready
                                                                    -> places (created/matched)

User input -> idea (raw) -> suggesting -> pipeline_result + place_suggestions -> ready
                                                          -> place (resolved)
                                                          -> idea card in UI
                         -> "Plan this" -> plan + plan_members (idea stays ready, reusable)
                                        -> shareCode -> /share/schedule?uid={shareCode}
                                        -> external user RSVP (auto-friend)
                                        -> calendar invite (GCal or SMS)
                                        -> notifications
```
