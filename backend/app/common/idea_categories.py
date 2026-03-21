"""Canonical idea / place category slugs shared by interpret, Places, and reel ingestion."""

from __future__ import annotations

CANONICAL_CATEGORIES: tuple[str, ...] = (
    "restaurant",
    "cafe",
    "bar",
    "nightlife",
    "arts-culture",
    "outdoors",
    "fitness",
    "shopping",
    "entertainment",
    "learning",
    "travel",
    "social",
    "other",
)

_CANONICAL_SET = frozenset(CANONICAL_CATEGORIES)


def normalize_category(raw: str | None) -> str:
    """Map legacy values to canonical slugs; unknown strings become ``other``."""
    if raw is None:
        return "other"
    key = raw.strip().lower()
    if not key:
        return "other"
    if key == "food-drink":
        return "restaurant"
    if key in _CANONICAL_SET:
        return key
    return "other"
