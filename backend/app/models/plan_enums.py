"""Plan-related enums. Match schema: planStatus, rsvpStatus, memberRole."""

from enum import Enum


class PlanStatus(str, Enum):
    draft = "draft"
    confirmed = "confirmed"
    completed = "completed"
    cancelled = "cancelled"


class RsvpStatus(str, Enum):
    pending = "pending"
    accepted = "accepted"
    declined = "declined"


class MemberRole(str, Enum):
    organizer = "organizer"
    member = "member"
