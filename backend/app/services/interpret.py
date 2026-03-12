import json
import logging
import re
from datetime import datetime, timedelta
from typing import Any, Optional

from openai import OpenAI

from app.common.config import getOpenAIApiKey

logger = logging.getLogger("roam.interpret")

CATEGORIES = [
    "food-drink", "arts-culture", "outdoors", "fitness",
    "shopping", "entertainment", "nightlife", "learning",
    "travel", "social", "other",
]

PREFERENCES = ["morning", "afternoon", "evening", "weekend", "any"]

SYSTEM_PROMPT = """You are the AI backend for Roam, a social planning app. Given a user's natural-language idea, extract structured data.

Return ONLY valid JSON with these fields:
{
  "refinedTitle": "A concise, polished version of the idea",
  "searchQuery": "Google Places search query to find the venue/location",
  "category": "one of: food-drink, arts-culture, outdoors, fitness, shopping, entertainment, nightlife, learning, travel, social, other",
  "preference": "one of: morning, afternoon, evening, weekend, any",
  "estimatedMinutes": 90,
  "tags": ["tag1", "tag2"],
  "invitees": ["FirstName1", "FirstName2"],
  "specificDatetime": "ISO 8601 datetime string or null",
  "taskAssignments": "person: task; person2: task2" or null
}

Rules:
- invitees: extract names after @ symbols. Return just the name part.
- specificDatetime: parse relative dates like "friday 7pm", "tomorrow at noon", "next saturday 3pm" relative to the current time provided.
- taskAssignments: if the input says something like "@Tyler bring drinks", extract "Tyler: bring drinks".
- If no place is mentioned, set searchQuery to the refined title.
- estimatedMinutes should be a reasonable estimate for the activity type.
"""


def interpret_with_openai(raw_input: str, current_time: str | None = None) -> dict[str, Any]:
    client = OpenAI(api_key=getOpenAIApiKey())

    now_str = current_time or datetime.utcnow().isoformat()
    user_message = f"Current time: {now_str}\n\nUser input: {raw_input}"

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_message},
            ],
            max_tokens=512,
            temperature=0.2,
        )

        raw = response.choices[0].message.content or "{}"
        cleaned = raw.strip()
        if cleaned.startswith("```"):
            lines = cleaned.split("\n")
            lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            cleaned = "\n".join(lines)

        result = json.loads(cleaned)
        result["aiEnriched"] = True
        result["modelName"] = "gpt-4o-mini"
        return result

    except Exception:
        logger.exception("OpenAI interpretation failed, falling back to keyword parser")
        return interpret_fallback(raw_input)


def interpret_fallback(raw_input: str) -> dict[str, Any]:
    """Keyword-based fallback when OpenAI is unavailable."""
    invitees = extract_invitees(raw_input)
    specific_datetime = extract_specific_datetime(raw_input)

    stripped = re.sub(r"@[a-zA-Z][a-zA-Z'-]*", "", raw_input)
    stripped = re.sub(
        r"\b(?:tomorrow|next\s+\w+|(?:mon|tues|wednes|thurs|fri|satur|sun)day)"
        r"(?:\s+at\s+|\s+)\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b",
        "", stripped, flags=re.IGNORECASE,
    )
    stripped = re.sub(r"\s+", " ", stripped).strip()
    if not stripped:
        stripped = "Make plans"

    category = _infer_category(stripped)
    preference = _infer_preference(raw_input, specific_datetime)
    estimated = _infer_duration(stripped, category)

    return {
        "refinedTitle": _title_case(stripped),
        "searchQuery": stripped,
        "category": category,
        "preference": preference,
        "estimatedMinutes": estimated,
        "tags": [],
        "invitees": invitees,
        "specificDatetime": specific_datetime,
        "taskAssignments": _extract_task_assignments(raw_input, invitees),
        "aiEnriched": False,
        "modelName": None,
    }


def extract_invitees(raw: str) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for match in re.finditer(r"@([a-zA-Z][a-zA-Z'-]*)", raw):
        name = match.group(1)
        key = name.lower()
        if key not in seen:
            seen.add(key)
            result.append(name[0].upper() + name[1:])
    return result


def _extract_task_assignments(raw: str, invitees: list[str]) -> str | None:
    tasks: list[str] = []
    for invitee in invitees:
        pattern = re.compile(rf"@{re.escape(invitee)}\s+([^@.,;!?]+)", re.IGNORECASE)
        m = pattern.search(raw)
        if m:
            task = re.sub(r"\s+", " ", m.group(1)).strip()
            task = re.sub(r"\b(with|and)\b.*$", "", task, flags=re.IGNORECASE).strip()
            if task:
                tasks.append(f"{invitee}: {task}")
    return "; ".join(tasks) if tasks else None


def extract_specific_datetime(raw: str) -> str | None:
    now = datetime.utcnow()
    lower = raw.lower()

    weekday_match = re.search(
        r"\b(?:next\s+|this\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)"
        r"(?:\s+at\s+|\s+)(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\b",
        lower,
    )
    if weekday_match:
        days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        target_idx = days.index(weekday_match.group(1)) if weekday_match.group(1) in days else -1
        parsed_time = _parse_time_token(weekday_match.group(2))
        if target_idx >= 0 and parsed_time:
            current_weekday = now.weekday()
            offset = (target_idx - current_weekday) % 7
            if offset == 0:
                offset = 7
            target = now + timedelta(days=offset)
            target = target.replace(
                hour=parsed_time["hour"], minute=parsed_time["minute"], second=0, microsecond=0
            )
            return target.isoformat()

    tomorrow_match = re.search(
        r"\btomorrow(?:\s+at\s+|\s+)?(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\b", lower
    )
    if tomorrow_match:
        parsed_time = _parse_time_token(tomorrow_match.group(1))
        if parsed_time:
            target = now + timedelta(days=1)
            target = target.replace(
                hour=parsed_time["hour"], minute=parsed_time["minute"], second=0, microsecond=0
            )
            return target.isoformat()

    return None


def _parse_time_token(token: str) -> dict[str, int] | None:
    normalized = token.strip().lower()
    if normalized == "noon":
        return {"hour": 12, "minute": 0}
    if normalized == "midnight":
        return {"hour": 0, "minute": 0}

    m = re.match(r"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$", normalized)
    if not m:
        return None

    hour = int(m.group(1))
    minute = int(m.group(2) or "0")
    meridiem = m.group(3)

    if meridiem == "pm" and hour < 12:
        hour += 12
    if meridiem == "am" and hour == 12:
        hour = 0
    if not meridiem and hour <= 7:
        hour += 12

    return {"hour": hour, "minute": minute}


def _title_case(raw: str) -> str:
    return " ".join(
        word[0].upper() + word[1:].lower() if word else ""
        for word in raw.split()
    )


def _infer_category(text: str) -> str:
    if re.search(r"\b(museum|gallery|met|concert|jazz|show)\b", text, re.IGNORECASE):
        return "arts-culture"
    if re.search(r"\b(drink|cocktail|bar|wine|night)\b", text, re.IGNORECASE):
        return "nightlife"
    if re.search(r"\b(dinner|lunch|brunch|restaurant|food|coffee)\b", text, re.IGNORECASE):
        return "food-drink"
    if re.search(r"\b(park|hike|garden|beach)\b", text, re.IGNORECASE):
        return "outdoors"
    if re.search(r"\b(class|workshop|learn|lecture)\b", text, re.IGNORECASE):
        return "learning"
    return "social"


def _infer_preference(text: str, specific_datetime: str | None) -> str:
    if specific_datetime:
        try:
            hour = datetime.fromisoformat(specific_datetime).hour
        except ValueError:
            return "any"
        if hour >= 17:
            return "evening"
        if hour >= 12:
            return "afternoon"
        return "morning"
    if re.search(r"\bweekend|saturday|sunday\b", text, re.IGNORECASE):
        return "weekend"
    if re.search(r"\bnight|drinks|dinner|show|concert|jazz\b", text, re.IGNORECASE):
        return "evening"
    if re.search(r"\bbrunch|coffee|breakfast\b", text, re.IGNORECASE):
        return "morning"
    return "any"


def _infer_duration(text: str, category: str) -> int:
    if re.search(r"\bmet|museum|concert|jazz|show\b", text, re.IGNORECASE):
        return 120
    if re.search(r"\bdrinks|cocktail|bar\b", text, re.IGNORECASE):
        return 120
    if re.search(r"\bdinner|restaurant|brunch\b", text, re.IGNORECASE):
        return 90
    if category == "outdoors":
        return 180
    return 90
