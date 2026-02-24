from collections.abc import Generator
from typing import Any, Callable, TypeVar

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, create_engine

from app.common.backendErrors import Conflict
from app.common.config import getDatabaseUrl


def _normalizeDatabaseUrl(databaseUrl: str) -> str:
    if databaseUrl.startswith("postgresql://"):
        return databaseUrl.replace("postgresql://", "postgresql+psycopg://", 1)
    return databaseUrl


databaseUrl = _normalizeDatabaseUrl(getDatabaseUrl())
engine = create_engine(
    databaseUrl,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    pool_timeout=30,
)


def getSession() -> Generator[Session, None, None]:
    session = Session(engine)
    try:
        yield session
    finally:
        session.close()


def getUniqueConstraintName(exc: IntegrityError) -> str | None:
    """Extract unique constraint name from an IntegrityError (DB-agnostic where possible)."""
    original = getattr(exc, "orig", None)
    constraintName = getattr(getattr(original, "diag", None), "constraint_name", None)
    if constraintName:
        return constraintName
    originalMessage = str(original)
    if "users_username_key" in originalMessage:
        return "users_username_key"
    if "users_email_key" in originalMessage:
        return "users_email_key"
    if "users_firebaseUid_key" in originalMessage:
        return "users_firebaseUid_key"
    if "unique_user_reel" in originalMessage:
        return "unique_user_reel"
    return None


def commitAndRefresh(
    session: Session,
    *objects: Any,
    constraintMessages: dict[str, str] | None = None,
) -> None:
    """
    Commit and refresh the given objects. On IntegrityError, rollback, map constraint
    name to message via constraintMessages, and raise Conflict(detail).
    """
    defaultMessage = "Resource already exists"
    messages = constraintMessages or {}
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        constraintName = getUniqueConstraintName(exc)
        detail = messages.get(constraintName, defaultMessage) if constraintName else defaultMessage
        raise Conflict(detail) from exc
    for obj in objects:
        session.refresh(obj)


T = TypeVar("T")


def handleIntegrityConflict(
    session: Session,
    lookupFn: Callable[[], T | None],
    conflictMessage: str,
) -> T:
    """
    Call after an IntegrityError: rollback, run lookupFn(); if it returns a value, return it;
    else raise Conflict(conflictMessage). Use in routes that return an existing row on duplicate.
    """
    session.rollback()
    result = lookupFn()
    if result is not None:
        return result
    raise Conflict(conflictMessage)

