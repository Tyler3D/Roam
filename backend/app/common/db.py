from collections.abc import Generator

from sqlmodel import Session, create_engine

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

