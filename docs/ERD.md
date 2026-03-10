# Entity Relationship Diagram

```mermaid
erDiagram
    users {
        uuid id PK
        text firebaseUid UK
        text username UK
        text email UK
        text displayName
        text photoUrl
        boolean isActive
        boolean emailVerified
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
        text placeName
        text placeAddress
        text category
        double latitude
        double longitude
        text googlePlaceId
        double confidence
        jsonb rawLlmOutput
        timestamptz createdAt
    }

    activity_pins {
        uuid id PK
        uuid userId FK
        uuid extractionId FK "nullable"
        text title
        text category
        text placeName
        text placeAddress
        double latitude
        double longitude
        text googlePlaceId
        integer rating "1-5"
        visitStatus visitStatus
        text notes
        text thumbnailUrl
        text reelUrl
        pinSource source
        timestamptz lastInteractedAt
        timestamptz createdAt
        timestamptz updatedAt
    }

    users ||--o{ ingestion_jobs : "submits"
    users ||--o{ activity_pins : "owns"
    ingestion_jobs ||--o{ extractions : "produces"
    extractions |o--o{ activity_pins : "confirms into"
```

## Enums

| Enum | Values |
|------|--------|
| `jobStatus` | `processing`, `done`, `failed` |
| `visitStatus` | `want`, `been` |
| `pinSource` | `reel`, `manual` |

## Relationships

| From | To | Type | On Delete |
|------|----|------|-----------|
| `ingestion_jobs.userId` | `users.id` | many-to-one | CASCADE |
| `extractions.jobId` | `ingestion_jobs.id` | many-to-one | CASCADE |
| `activity_pins.userId` | `users.id` | many-to-one | CASCADE |
| `activity_pins.extractionId` | `extractions.id` | many-to-one (nullable) | SET NULL |
