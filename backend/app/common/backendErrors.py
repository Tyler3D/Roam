"""
Generic backend errors for consistent API responses. All are subclasses of
FastAPI's HTTPException so the global exception handler in app.py logs and
returns them correctly. Use e.g. raise BadRequest("Email not verified").
"""

from fastapi import HTTPException


class RoamBackendError(HTTPException):
    """Base for all Roam API errors. Subclasses fix status_code and optional default detail."""

    def __init__(self, detail: str, status_code: int = 500):
        super().__init__(status_code=status_code, detail=detail)


class BadRequest(RoamBackendError):
    """400 Bad Request."""

    def __init__(self, detail: str = "Bad request"):
        super().__init__(detail=detail, status_code=400)


class Unauthorized(RoamBackendError):
    """401 Unauthorized."""

    def __init__(self, detail: str = "Unauthorized"):
        super().__init__(detail=detail, status_code=401)


class Forbidden(RoamBackendError):
    """403 Forbidden."""

    def __init__(self, detail: str = "Forbidden"):
        super().__init__(detail=detail, status_code=403)


class NotFound(RoamBackendError):
    """404 Not Found."""

    def __init__(self, detail: str = "Not found"):
        super().__init__(detail=detail, status_code=404)


class Conflict(RoamBackendError):
    """409 Conflict (e.g. duplicate resource)."""

    def __init__(self, detail: str = "Conflict"):
        super().__init__(detail=detail, status_code=409)


class RateLimited(RoamBackendError):
    """429 Too Many Requests."""

    def __init__(self, detail: str = "Too many requests"):
        super().__init__(detail=detail, status_code=429)


class UnprocessableEntity(RoamBackendError):
    """422 Unprocessable Entity (validation)."""

    def __init__(self, detail: str = "Unprocessable entity"):
        super().__init__(detail=detail, status_code=422)


class InternalServerError(RoamBackendError):
    """500 Internal Server Error."""

    def __init__(self, detail: str = "Internal server error"):
        super().__init__(detail=detail, status_code=500)


class ProviderRateLimitError(Exception):
    """Upstream provider (Google Maps, Gemini, etc.) returned 429."""
