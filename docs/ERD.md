# Entity Relationship Diagram

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
        jsonb tags
        boolean isActive
        boolean isOnboarded
        boolean isExternal
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
        text_arr placeTypes
        timestamptz createdAt
    }

    enrichments {
        uuid id PK
        text refinedTitle
        text category
        text searchQuery
        text_arr tags
        integer estimatedMinutes
        text preference
        boolean aiEnriched
        text modelName
        jsonb rawOutput
        jsonb confidence
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
        text savedLink
        uuid placeId FK "nullable"
        uuid enrichmentId FK "nullable"
        timestamptz createdAt
        timestamptz updatedAt
    }

    plans {
        uuid id PK
        uuid creatorId FK
        uuid placeId FK "nullable"
        uuid ideaId FK "nullable"
        uuid enrichmentId FK "nullable"
        text title
        timestamptz scheduledAt
        planStatus status
        text shareCode UK
        text rawPrompt
        integer estimatedMinutes
        text calendarEventId
        integer covers
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
        text task
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

    notifications {
        uuid id PK
        uuid userId FK
        notificationType type
        uuid planId FK "nullable"
        text title
        text body
        boolean isRead
        timestamptz createdAt
    }

    ingestion_jobs {
        uuid id PK
        uuid userId FK
        text reelUrl
        text shareText
        text lpTitle
        text ogDescription
        text ogKeywords
        jobStatus status
        text error
        timestamptz createdAt
        timestamptz updatedAt
    }

    extractions {
        uuid id PK
        uuid jobId FK
        uuid placeId FK "nullable"
        double confidence
        jsonb rawLlmOutput
        timestamptz createdAt
    }

    users ||--o{ friendships : "requests"
    users ||--o{ friendships : "receives"
    users ||--o{ ideas : "creates"
    users ||--o{ plans : "creates"
    users ||--o{ plan_members : "joins"
    users ||--o{ plan_messages : "sends"
    users ||--o{ notifications : "receives"
    users ||--o{ ingestion_jobs : "submits"

    enrichments ||--o{ ideas : "enriches"
    enrichments ||--o{ plans : "enriches"

    places ||--o{ ideas : "located at"
    places ||--o{ plans : "hosts"
    places ||--o{ extractions : "resolved from"

    ideas ||--o{ plans : "promoted to"

    plans ||--o{ plan_members : "has"
    plans ||--o{ plan_tasks : "has"
    plans ||--o{ plan_messages : "contains"
    plans ||--o{ notifications : "triggers"

    plan_members ||--o{ plan_tasks : "assigned"

    ingestion_jobs ||--o{ extractions : "produces"
```

## Enums

| Enum | Values | Used By |
|------|--------|---------|
| `jobStatus` | `processing`, `done`, `failed` | `ingestion_jobs.status` |
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
| `plans.enrichmentId` | `enrichments.id` | many-to-one (nullable) | SET NULL |
| `ideas.userId` | `users.id` | many-to-one | CASCADE |
| `ideas.placeId` | `places.id` | many-to-one (nullable) | SET NULL |
| `ideas.enrichmentId` | `enrichments.id` | many-to-one (nullable) | SET NULL |
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
| `ingestion_jobs.userId` | `users.id` | many-to-one | CASCADE |
| `extractions.jobId` | `ingestion_jobs.id` | many-to-one | CASCADE |
| `extractions.placeId` | `places.id` | many-to-one (nullable) | SET NULL |

## Data Flow

```
Reel shared -> ingestion_job -> extraction -> place (created/matched)

User input -> idea (raw) -> enrichment (AI) -> place (resolved)
                                            -> idea card in UI
                         -> "Plan this" -> plan + plan_members
                                        -> shareCode -> /share/schedule?uid={shareCode}
                                        -> external user RSVP (auto-friend)
                                        -> calendar invite (GCal or SMS)
                                        -> notifications
```
