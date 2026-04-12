# CLAUDE.md

## What is Roam

Roam turns Instagram and TikTok reels into a personal map of places to visit. Users share reels into the app via the iOS share sheet, and an AI pipeline extracts the places mentioned — restaurants, cafes, bars, events — and turns them into **ideas** pinned on a map. Users can build maps solo or collaboratively with friends through **collections**.

Roam is a higher-quality alternative to Beli. Where Beli relies on user rankings layered on top of Google Maps data, Roam ingests reel content — thumbnails, video frames, captions, metadata — to create a richer representation of a place. A reel captures not just _where_ something is, but _what's worth experiencing there_. Because reels often describe events and experiences at a location, Roam has a temporal dimension that pure review apps lack. And when multiple users send reels about the same place — different reels, or even the same one — Roam can measure how popular and influential a place is, and how widespread its reach.

## Core Concepts

### Places

Global, geographic entities deduplicated by `googlePlaceId`. One real-world location = one `places` row, regardless of how many users or reels reference it. Places are public infrastructure — they store name, address, coordinates, category, opening hours, and Google place types.

### Ideas

Per-user, private by default. An idea is a user's personal connection to a place — "amazing oat milk latte at Blue Bottle" or "live jazz every Thursday." Ideas link to a place and optionally back to the reel they came from. Multiple ideas can point to the same place, each adding a different layer of texture. Ideas are only visible to other users when shared via a collection.

### Collections

A collection is a group of ideas — and visually, a shared map. Every user has a personal default collection ("My saves") created automatically. Users can also create shared collections and invite friends. When viewing the Map tab, pins come from the user's personal collection plus any shared collections they belong to. Each contributor's pins are color-coded so you can see who saved what.

The primary value prop: **build a shared map with friends from the reels you all save.**

### Plans (future — built but hidden)

Plans are schedulable, shareable events tied to an idea or place. They support invites, RSVPs, calendar integration (Google Calendar or SMS), and team coordination. Plans are fully built but hidden behind an alpha feature flag. They are still in product planning and may be added to production in the future. The product team is still determining what role plans play in the app.

### Friendships

Currently a lightweight social graph. Users must be friends to join shared collections. The share-code flow for plans auto-friends users. The social layer could become more prominent in the future — shared maps are strong product value — but for now friendships primarily enable collection collaboration rather than being a standalone feature.

## The Reel Ingestion Pipeline

### Flow

1. **Share**: User shares a reel URL from Instagram/TikTok via the iOS share sheet
2. **Extract**: App uploads frames, thumbnail, and metadata (title, captions, OG tags) to the backend
3. **Vision**: Gemini 2.5 Flash analyzes the visual and text content, extracting candidate places with confidence scores
4. **Filter**: Candidates below 0.7 confidence are discarded
5. **Resolve**: Each surviving candidate is resolved to a Google Maps place via Text Search API. Places are deduplicated — if the `googlePlaceId` already exists, the existing place row is reused
6. **Stage or promote**: Behavior depends on candidate count (see below)

### Single vs. Multi-Candidate Behavior

- **1 candidate above threshold**: Auto-promoted directly to an idea (no user review). Reel status → `promoted`. This is gated behind the `auto_promote_single_candidate` feature flag — users can disable it in Account Settings to always require review.
- **0 or 2+ candidates**: Staged as `reel_ingest_candidates`. Reel status → `needs_review`. User sees candidates in the review UI and selects which to promote.

### Promotion

When a user promotes a candidate, an idea is created, linked to the resolved place and the user's personal collection (plus any shared collections they choose). The candidate's `promotedIdeaId` is set. The reel status moves to `promoted`.

## Data Model Principles

### Places are global, ideas are per-user

A place is an objective geographic entity. An idea is a subjective, personal save. This separation means the same Blue Bottle SoHo can have dozens of ideas across different users, each capturing a different experience — and all deduplicated to one place row.

### Pipeline guess vs. user override

The ingestion pipeline resolves each candidate to a place automatically via Google Maps. But users can always override the pipeline's choice by editing the location in the LocationPickerSheet (dragging the map pin, searching a new address via Google Places Autocomplete).

Both are tracked:

- **Pipeline guess**: stored on `reel_ingest_candidates.resolvedPlaceId` — never overwritten by user actions
- **User confirmation**: stored in `reel_candidate_user_places` — a per-user, per-candidate join table that records the place the user actually confirmed, with coordinates, address, and a `source` field (`'pipeline'` or `'user'`)

This means you can always compare what the pipeline thought vs. what the user chose. When the API returns candidate data, user-confirmed values take priority over pipeline-resolved values.

The `UNIQUE(candidate_id, user_id)` constraint means each user gets one confirmation per candidate. But different users can each have their own row — so if 50 users save the same reel, you get 50 independent data points on where that reel's place is. This enables future features like consensus detection (do most users agree with the pipeline?) and data quality scoring.

### Place deduplication

Places are deduplicated on `googlePlaceId` (UNIQUE constraint). The pipeline checks for an existing place before creating a new one. This ensures that when 10 reels mention the same restaurant, they all point to the same `places` row.

## Key Product Rules

- **Users can always override the pipeline.** The location picker lets users correct or change the place for any candidate, before or after promotion.
- **Ideas are private by default.** Only visible to the owner unless shared via a collection.
- **One place per googlePlaceId.** No duplicate place records for the same real-world location.
- **Multi-candidate reels always require review.** Only single-candidate reels can be auto-promoted.
- **Personal default collection always exists.** Every idea is linked to it automatically. It cannot be deleted.
- **Only friends can join shared collections.** Enforced server-side.

## Current App Structure (Production)

Three tabs:

- **Ideas** — Grid of saved ideas
- **Map** — Google Maps with pins from personal + shared collections, filterable by category and collection
- **Reels** — Ingestion queue: processing, needs review, promoted, failed

Account Settings (via profile) includes a toggle for auto-promote behavior.

Plans and Drafts tabs exist but are hidden behind the alpha flag (`alphaHeavyDevelopmentUnsafe`).

## Future Directions

- **Temporal ideas**: Reels often describe events ("jazz night at Blue Bottle this Thursday"). Ideas could carry date/time metadata, enabling calendar-aware discovery and expiration.
- **Cross-user discovery**: "New ideas at places you already go to" — surfacing other users' ideas at your known places (with privacy controls).
- **Trending places**: Aggregating idea counts and reel frequency per place to measure popularity. Multiple users sending reels about the same place = signal. Different reels about the same place = stronger signal than the same reel shared multiple times.
- **GCal integration**: Turning reel-derived ideas into calendar events automatically.
- **Plans in production**: Full event coordination (invites, RSVPs, calendar sync) is built and waiting for product clarity on its role.
- **Richer place profiles**: Combining Google Maps data, reel descriptions, thumbnails/video, user rankings, and temporal data to build place representations that go beyond what Google Maps or Beli offer alone.
- **Influence measurement**: Tracking how many distinct reels reference a place, from how many distinct users, to gauge both popularity and the breadth of a place's cultural reach.

## Python naming (backend)

**Use camelCase for function names** in this repo (including private helpers: `_getOrCreatePlaceRead`, not `_get_or_create_place_read`). This matches the rest of the Roam backend style and differs from PEP 8’s usual `snake_case` for functions—follow Roam’s convention here. Module-level constants, class names, and SQLModel/Pydantic field names keep their existing patterns (e.g. `googlePlaceId` on models).

## Developer Workflow

### OpenAPI Codegen

The API contract flows from FastAPI → OpenAPI JSON → Swift types + TypeScript types. After any backend model or route change:

1. **Generate OpenAPI spec**: `bash scripts/export_openapi.sh` — writes `contracts/openapi.json` and `RoamOpenAPI/Sources/RoamOpenAPI/openapi.yaml`
2. **Build Swift package**: `cd RoamOpenAPI && swift build` — regenerates `Types.swift` from the YAML
3. **Generate frontend types**: `cd frontend && npx openapi-typescript ../contracts/openapi.json --enum -o src/models/generated/api.d.ts`

The export script requires `backend/.venv-export` (Python 3.12+ with project dependencies). See `scripts/export_openapi.sh` for setup instructions.
