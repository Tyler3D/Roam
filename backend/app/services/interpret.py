import hashlib
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.common.config import getGeminiApiKey
from app.common.idea_categories import CANONICAL_CATEGORIES, normalize_category

logger = logging.getLogger("roam.interpret")

CATEGORIES = list(CANONICAL_CATEGORIES)

PREFERENCES = ["morning", "afternoon", "evening", "weekend", "any"]


def _load_scribble_prompt() -> str:
    path = Path(__file__).resolve().parent.parent / "prompts" / "scribble_interpret.md"
    return path.read_text(encoding="utf-8")


SCRIBBLE_SYSTEM_PROMPT = _load_scribble_prompt()


class ScribbleInterpretOutput(BaseModel):
    refinedTitle: str
    searchQuery: str
    category: str
    preference: str
    estimatedMinutes: int
    invitees: list[str] = Field(default_factory=list)
    specificDatetime: Optional[str] = None
    taskAssignments: Optional[str] = None


_TRANSIENT_KEYWORDS = ("rate", "503", "timeout", "overloaded", "quota", "resource exhausted")


def interpret_idea(raw_input: str, current_time: str | None = None, _retries: int = 2) -> dict[str, Any]:
    """Interpret user idea using Gemini with retry on transient errors."""
    import time as _time
    client = genai.Client(api_key=getGeminiApiKey())
    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

    now_str = current_time or datetime.now(timezone.utc).isoformat()
    user_message = f"Current time: {now_str}\n\nUser input: {raw_input}"

    for attempt in range(_retries + 1):
        try:
            response = client.models.generate_content(
                model=model,
                contents=user_message,
                config=types.GenerateContentConfig(
                    system_instruction=SCRIBBLE_SYSTEM_PROMPT,
                    response_mime_type="application/json",
                    response_schema=ScribbleInterpretOutput,
                    temperature=0.2,
                    max_output_tokens=512,
                ),
            )

            parsed = ScribbleInterpretOutput.model_validate_json(response.text)
            result = parsed.model_dump()
            result["category"] = normalize_category(result.get("category"))
            # Validate outputs are within sane ranges; correct silently if not.
            if result.get("preference") not in PREFERENCES:
                result["preference"] = "any"
            est = result.get("estimatedMinutes", 0)
            if not isinstance(est, int) or not (15 <= est <= 480):
                result["estimatedMinutes"] = _infer_duration(raw_input, result.get("category", "social"))
            result["aiEnriched"] = True
            result["modelName"] = model
            return result

        except Exception as e:
            is_transient = any(kw in str(e).lower() for kw in _TRANSIENT_KEYWORDS)
            if attempt < _retries and is_transient:
                _time.sleep(1.5 ** attempt)
                logger.warning("Gemini transient error on attempt %d, retrying: %s", attempt + 1, e)
                continue
            logger.exception("Gemini interpretation failed on attempt %d, falling back", attempt + 1)
            break

    return interpret_fallback(raw_input)


def interpret_fallback(raw_input: str) -> dict[str, Any]:
    """Keyword-based fallback when Gemini is unavailable."""
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
        "category": normalize_category(category),
        "preference": preference,
        "estimatedMinutes": estimated,
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
    now = datetime.now(timezone.utc)
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
    if re.search(
        r"\b(nightclub|night club|rave|edm|afterhours|dance club)\b", text, re.IGNORECASE
    ):
        return "nightlife"
    if re.search(
        r"\b(bar|pub|cocktail|wine bar|rooftop bar|taproom|brewery|speakeasy)\b",
        text,
        re.IGNORECASE,
    ):
        return "bar"
    if re.search(
        r"\b(bottomless|mimosas?|boozy brunch|drunk brunch)\b", text, re.IGNORECASE
    ):
        return "bar"
    if re.search(r"\b(coffee|café|cafe|bakery|espresso)\b", text, re.IGNORECASE):
        return "cafe"
    if re.search(r"\b(dinner|lunch|brunch|restaurant|food|eat|dining)\b", text, re.IGNORECASE):
        return "restaurant"
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
    if re.search(r"\bdrinks|cocktail|bar|nightclub|rave\b", text, re.IGNORECASE):
        return 120
    if re.search(r"\bdinner|restaurant|brunch\b", text, re.IGNORECASE):
        return 90
    if category == "cafe":
        return 60
    if category in ("bar", "nightlife"):
        return 120
    if category == "outdoors":
        return 180
    return 90


def get_scribble_prompt_version() -> str:
    """Return a short hash of the current prompt for pipeline_results.promptVersion."""
    h = hashlib.md5(SCRIBBLE_SYSTEM_PROMPT.encode()).hexdigest()[:8]
    return f"scribble-{h}"
