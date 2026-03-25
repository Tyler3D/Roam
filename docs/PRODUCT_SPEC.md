# Product Spec: Roam

## Vision

Roam turns the reels you share with friends into a living, shared map of places to experience together.

Every week, millions of people see a reel about a restaurant, bar, or event and think "I need to go there" — then immediately forget about it. Roam captures that intent at the moment of sharing, extracts the place, and pins it to a map that you and your friends build together over time.

## Target Audience

**Primary**: Intentional, organized 20-somethings (Gen Z) living in urban areas. They share reels with friends constantly — restaurants, cafes, pop-ups, events — but struggle to keep track of what they've seen. They want a system that turns casual discovery into actionable plans.

**Characteristics**:
- Share 5-15+ reels per week with friends about places and experiences
- Live in cities with dense, fast-moving food/drink/event scenes (NYC, LA, SF, Chicago, London)
- Already use Google Maps saved places or notes apps to track recommendations, but find them inadequate
- Value curation over volume — they don't want every restaurant in the city, they want *their* places and their friends' picks
- Social but deliberate — they plan outings, not just browse

## Competitive Landscape

### Google Maps Saved Places
Google Maps lets you star or save places into lists. It's the most common workaround for "remember this place."

**Where it falls short**:
- Manual entry only — you have to search for the place and save it yourself
- No context — a saved pin tells you nothing about *why* you saved it or what experience was recommended
- No social layer — lists are shareable but not collaborative in real-time
- No reel integration — the primary way Gen Z discovers places (via reels) has no connection to the primary way they track places (Google Maps)

### Beli
Beli lets users rank restaurants and see what friends think. It adds a social/opinion layer on top of Google Maps data.

**Where it falls short**:
- Input is manual — users type reviews and ratings by hand
- Limited to restaurants (primarily)
- No reel-based discovery — the richest source of place recommendations (short-form video) is completely disconnected
- Place data is Google Maps + user rankings, nothing more

### Roam's Advantage
Roam ingests reel content — thumbnails, video frames, captions, metadata — to create a richer representation of a place than either Google Maps or Beli. A reel captures not just *where* something is, but *what's worth experiencing there*.

Because reels often describe events and time-bound experiences ("jazz night every Thursday," "pop-up this weekend"), Roam has a **temporal dimension** that pure review/ranking apps lack.

And when multiple users send reels about the same place — different reels, or even the same one — Roam can measure how **popular** a place is, and how **widespread** its cultural reach. This is signal that neither Google Maps nor Beli can capture.

## User Stories

### Core Flow
> As a user, I see a reel about a great restaurant on Instagram. I tap share → Roam. Within seconds, the place appears in my reel queue. The AI extracts the restaurant name and location. I tap "Save" and it's pinned to my map.

### Shared Maps
> As a user, I create a collection called "NYC Eats" and invite three friends. When any of us shares a reel about a restaurant, it shows up on our shared map. I can see who saved what — each friend's pins are color-coded. When we're deciding where to eat Friday night, we open the map and pick from places we've all been collecting.

### Review & Override
> As a user, I share a reel but the AI picks the wrong location. I tap "Edit" on the candidate, search for the correct address, drag the pin to the right spot, and confirm. My correction is saved and the map updates immediately.

### Multi-Place Reels
> As a user, I share a reel that says "5 best coffee shops in SoHo." The AI extracts all 5 candidates. I review them, select the 3 I actually want to save, and promote them in one tap. Each becomes its own idea pinned on my map.

### Discovery (Future)
> As a user, I open my map and see a "trending" badge on a place I've already saved. Three of my friends have also saved reels about it this week. I tap it and see the different reels — one about the food, one about the vibe, one about a pop-up event happening Saturday.

## Core Concepts

### Places
Global, geographic entities. One real-world location = one record, regardless of how many users or reels reference it. Places store name, address, coordinates, category, and opening hours. Deduplicated by Google Place ID.

### Ideas
Per-user, private by default. An idea is a user's personal connection to a place — "amazing oat milk latte at Blue Bottle" or "live jazz every Thursday." Ideas link to a place and optionally back to the reel they came from. Multiple ideas can point to the same place, each adding a different layer of texture. Ideas are only visible to others when shared via a collection.

### Collections
A collection is a group of ideas — and visually, a shared map. Every user has a personal default collection ("My saves") created automatically. Users can also create shared collections and invite friends. When viewing the Map tab, pins come from the user's personal collection plus any shared collections they belong to. Each contributor's pins are color-coded.

### Plans (Future)
Schedulable, shareable events tied to an idea or place. Plans support invites, RSVPs, calendar integration, and team coordination. Fully built but hidden behind an alpha feature flag while the product team determines their role.

### Friendships
A lightweight social graph that enables collection collaboration. Users must be friends to join shared collections. The social layer could expand in the future — shared maps are strong product value — but friendships currently serve as the trust layer for collaboration.

## The Reel Ingestion Pipeline

1. **Share**: User shares a reel URL from Instagram/TikTok via the iOS share sheet
2. **Extract**: App uploads frames, thumbnail, and metadata (title, captions, OG tags)
3. **Vision**: AI (Gemini 2.5 Flash) analyzes visual and text content, extracting candidate places with confidence scores
4. **Filter**: Candidates below the confidence threshold are discarded
5. **Resolve**: Each candidate is matched to a Google Maps place. Existing places are reused — no duplicates
6. **Stage or promote**:
   - **1 candidate**: Auto-promoted directly to an idea (skips review). Toggleable per user.
   - **Multiple candidates**: Staged for user review. User selects which to promote.

## Current Product State

### What's live (production)
- **Reel ingestion**: Share sheet → AI extraction → candidate review → promote to ideas
- **Map**: Google Maps with pins from personal + shared collections, filterable by category and collection
- **Collections**: Personal default + shared collections with friends
- **Location editing**: Users can override AI-resolved places via search + map pin
- **Auto-promote**: Single high-confidence candidates skip review (toggleable in settings)

### What's built but hidden
- **Plans**: Full event coordination — scheduling, invites, RSVPs, Google Calendar integration, share codes

### What's planned
- Temporal ideas (events with dates/times)
- Cross-user discovery ("new ideas at places you already go to")
- Trending places (popularity + reach signals from reel frequency)
- GCal integration for reel-derived ideas
- Richer place profiles combining maps data, reel content, user data, and temporal signals
- Influence measurement (distinct reels × distinct users per place)

## Key Product Principles

1. **The user is always right.** The AI pipeline is a starting point, not the final word. Users can always override, correct, or modify what the system suggests.
2. **Ideas are private by default.** Your saves are yours. They only become visible to others when you explicitly share them via a collection.
3. **One place, many ideas.** A place is an objective geographic entity. Ideas are subjective, personal connections to that place. Multiple ideas from multiple users add texture to a single place.
4. **Reels are the funnel.** The share sheet is the top of the funnel. Everything downstream — extraction, review, maps, collections — serves the moment when someone sees a reel and thinks "I need to go there."
5. **Shared maps are the value.** Solo maps are useful. Shared maps with friends are *the* product. Collections are the core social unit.
