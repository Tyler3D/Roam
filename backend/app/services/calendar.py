"""Google Calendar integration: create events via API when OAuth token available."""

import logging
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from sqlmodel import Session

from app.services.oauth_tokens import get_token_for_user, refresh_google_token, upsert_token

logger = logging.getLogger("roam.calendar")


def create_calendar_event(
    session: Session,
    user_id: UUID,
    title: str,
    start_time: datetime,
    duration_minutes: int,
    location: str | None = None,
    description: str | None = None,
    timezone: str = "UTC",
) -> dict[str, Any] | None:
    """
    Create a Google Calendar event. Returns {eventId, eventLink} on success, None on failure.
    On 401, attempts token refresh and retries once.
    timezone: IANA timezone (e.g. America/New_York). Frontend passes via Intl.DateTimeFormat().resolvedOptions().timeZone.
    """
    access_token, _ = get_token_for_user(session, user_id, "google")
    if not access_token:
        return None

    def _do_insert(token: str) -> dict[str, Any]:
        creds = Credentials(token=token)
        service = build("calendar", "v3", credentials=creds, cache_discovery=False)
        end_time = start_time + timedelta(minutes=duration_minutes)

        body: dict[str, Any] = {
            "summary": title,
            "start": {"dateTime": start_time.isoformat(), "timeZone": timezone},
            "end": {"dateTime": end_time.isoformat(), "timeZone": timezone},
        }
        if location:
            body["location"] = location
        if description:
            body["description"] = description

        event = service.events().insert(calendarId="primary", body=body).execute()
        return {
            "eventId": event.get("id", ""),
            "eventLink": event.get("htmlLink", ""),
        }

    try:
        return _do_insert(access_token)
    except HttpError as e:
        if e.resp.status in (401, 403):
            logger.info("Calendar API returned %s, attempting token refresh", e.resp.status)
            new_token = refresh_google_token(session, user_id)
            if new_token:
                session.commit()
                try:
                    return _do_insert(new_token)
                except HttpError:
                    pass
        logger.warning("Calendar event creation failed: %s", e)
    except Exception as e:
        logger.exception("Calendar event creation failed: %s", e)

    return None
