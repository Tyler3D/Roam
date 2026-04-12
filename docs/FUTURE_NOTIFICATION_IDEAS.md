# Future Notification Ideas

Aspirational notification concepts that depend on features not yet in production. Documented here for future reference -- not part of current implementation scope.

## Temporal / Event Nudge -- "That pop-up you saved is this weekend"

- **Depends on**: Temporal ideas with date/time metadata extracted from reels.
- **Trigger**: An idea has an associated event date approaching (e.g., within 3 days).
- **Why it matters**: Reels often describe time-bound experiences ("jazz night every Thursday," "pop-up this weekend"). If Roam can extract and store event timing during ingestion, it can remind users before the window closes.
- **Tap action**: Opens the idea on the map with the reel and event details.
- **Complexity**: Requires extending the ingestion pipeline's Gemini prompt to extract dates, a new `eventDate` / `recurrence` field on ideas or places, and a scheduled job to scan upcoming events.

## "You Should Go" Nudge -- "[Place] you saved 3 weeks ago -- this weekend?"

- **Trigger**: A saved idea is aging (2-4 weeks old, configurable) and the user hasn't visited or interacted with it.
- **Why it matters**: Saved ideas lose urgency over time. A gentle weekend nudge re-surfaces forgotten spots at a moment when the user might actually go.
- **Risk**: Can feel naggy. Needs careful frequency capping (max 1/week, and stop after 2-3 nudges for the same place). Could pair with weather data or weekend timing for relevance.
- **Tap action**: Opens the place on the map.

## Post-Visit Reflection -- "How was [Place]?"

- **Depends on**: Location-based visit detection (user was within ~100m of a saved place for 20+ minutes).
- **Trigger**: After a detected visit to a place the user has a saved idea for.
- **Why it matters**: Closes the loop from "I want to go" to "I went, here's what I thought." Enables a feedback loop: rate, add notes, share experience with collection members.
- **Long-term value**: This is how Roam builds first-party quality data that rivals Beli -- organic post-visit impressions rather than prompted reviews.
- **Privacy**: Requires "always" or "while using" location permission. Must be clearly communicated to users and easy to disable.
- **Tap action**: Opens a lightweight review/note screen for the place.

## New Friend Onboarding -- "[Name] just joined Roam"

- **Depends on**: Contact matching (access to phone contacts with permission).
- **Trigger**: A contact from the user's phone joins the app and creates an account.
- **Why it matters**: Classic growth mechanic, but framed through Roam's lens. Instead of "follow them," the prompt is "send them a collection invite" -- immediately establishing the shared map dynamic.
- **Copy**: "[Name] just joined Roam -- add them to a collection?"
- **Tap action**: Opens friend request flow or collection invite picker.

## Micro-Signals on Ideas -- "Interested" / "Save to my map"

- **Concept**: When a friend's idea appears in a shared collection or via a notification, other users can tap lightweight reactions ("Interested," "Save to my map") without creating a full idea of their own.
- **Notification potential**: "[Name] is interested in [Place] you saved" -- gives the saver ambient awareness that their save resonated. Could be a lightweight alternative to messaging.
- **Risk**: Could add noise. Needs to be very low-friction (one tap, no confirmation) and the resulting notification should be batched into digests rather than pushed individually.
