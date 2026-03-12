import logging
from datetime import datetime, timedelta
from typing import Any

logger = logging.getLogger("roam.scheduling")


def suggest_time_slots(
    preference: str = "any",
    estimated_minutes: int = 60,
    opening_hours: list[dict[str, Any]] | None = None,
    num_slots: int = 5,
) -> list[dict[str, Any]]:
    """Generate suggested time slots based on preference and opening hours.

    Returns a list of slot dicts: {start: ISO string, end: ISO string, label: str, score: float}
    """
    now = datetime.utcnow()
    slots: list[dict[str, Any]] = []

    preference_hours = {
        "morning": [(9, 0), (10, 0), (11, 0)],
        "afternoon": [(12, 0), (13, 0), (14, 0), (15, 0)],
        "evening": [(17, 0), (18, 0), (19, 0), (20, 0)],
        "weekend": [(10, 0), (12, 0), (14, 0), (16, 0), (18, 0)],
        "any": [(10, 0), (12, 0), (14, 0), (17, 0), (19, 0)],
    }

    hours = preference_hours.get(preference, preference_hours["any"])

    for day_offset in range(1, 8):
        target_date = now + timedelta(days=day_offset)

        if preference == "weekend" and target_date.weekday() < 5:
            continue

        for hour, minute in hours:
            start = target_date.replace(hour=hour, minute=minute, second=0, microsecond=0)
            if start <= now:
                continue

            end = start + timedelta(minutes=estimated_minutes)

            day_label = _format_day_label(start, now)
            time_label = start.strftime("%-I:%M %p").lstrip("0")

            slots.append({
                "start": start.isoformat(),
                "end": end.isoformat(),
                "label": f"{day_label} at {time_label}",
                "score": _score_slot(start, preference),
            })

            if len(slots) >= num_slots * 3:
                break
        if len(slots) >= num_slots * 3:
            break

    slots.sort(key=lambda s: s["score"], reverse=True)
    return slots[:num_slots]


def _format_day_label(dt: datetime, now: datetime) -> str:
    tomorrow = now + timedelta(days=1)
    if dt.date() == tomorrow.date():
        return "Tomorrow"
    return dt.strftime("%A, %b %-d")


def _score_slot(dt: datetime, preference: str) -> float:
    score = 1.0
    hour = dt.hour

    if preference == "morning" and 8 <= hour <= 11:
        score += 2.0
    elif preference == "afternoon" and 12 <= hour <= 16:
        score += 2.0
    elif preference == "evening" and 17 <= hour <= 21:
        score += 2.0
    elif preference == "weekend" and dt.weekday() >= 5:
        score += 2.0

    days_out = (dt - datetime.utcnow()).days
    if 1 <= days_out <= 3:
        score += 1.0
    elif 4 <= days_out <= 5:
        score += 0.5

    if dt.weekday() in (4, 5):
        score += 0.5

    return score
