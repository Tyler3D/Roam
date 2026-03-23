from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any


GENERIC_QUERY_TERMS = {
    "restaurant",
    "bar",
    "cafe",
    "coffee",
    "food",
    "drinks",
    "date",
    "plan",
    "activity",
    "thing to do",
}


@dataclass
class InterpretValidationResult:
    uncertainty: dict[str, Any]
    normalized: dict[str, Any]


def _is_generic_query(query: str) -> bool:
    q = re.sub(r"\s+", " ", query.strip().lower())
    if not q:
        return True
    if q in GENERIC_QUERY_TERMS:
        return True
    if len(q.split()) == 1 and q in {"museum", "park", "gym", "nightlife", "shopping"}:
        return True
    return False


def validate_interpret_output(result: dict[str, Any]) -> InterpretValidationResult:
    normalized = dict(result)

    invitees = normalized.get("invitees") or []
    task_assignments = normalized.get("taskAssignments")
    specific_datetime = normalized.get("specificDatetime")
    search_query = str(normalized.get("searchQuery") or "").strip()

    query_generic = _is_generic_query(search_query)
    invitees_ambiguous = bool(invitees and any(len(str(n).strip()) < 3 for n in invitees))
    task_ambiguous = bool(task_assignments and len(str(task_assignments).strip()) < 6)
    datetime_uncertain = bool(specific_datetime and "T" not in str(specific_datetime))

    flags = {
        "queryTooGeneric": query_generic,
        "inviteesAmbiguous": invitees_ambiguous,
        "taskAssignmentsAmbiguous": task_ambiguous,
        "datetimeUncertain": datetime_uncertain,
    }
    reasons: list[str] = []
    if query_generic:
        reasons.append("Search query is too generic for reliable place matching.")
    if invitees_ambiguous:
        reasons.append("Some @mention names are too short/ambiguous to auto-resolve.")
    if task_ambiguous:
        reasons.append("Task assignment extraction is low confidence.")
    if datetime_uncertain:
        reasons.append("Specific datetime could not be parsed reliably.")

    # Simple confidence calibration to drive UX confirmation.
    confidence = 1.0
    for active in flags.values():
        if active:
            confidence -= 0.2
    confidence = max(0.0, min(1.0, confidence))

    uncertainty = {
        "requiresConfirmation": any(flags.values()),
        "confidence": confidence,
        "flags": flags,
        "reasons": reasons,
    }

    normalized["uncertainty"] = uncertainty
    return InterpretValidationResult(uncertainty=uncertainty, normalized=normalized)
