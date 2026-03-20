"""
HTTP helpers for API responses: security headers, CORS on responses, JSON error
bodies, request id, and structured error logging.

Used by `rateLimiter` middleware and by global FastAPI exception handlers in
`app.py` (middleware cannot rely on those handlers for HTTPException, but routes can).
"""

from __future__ import annotations

import logging
import uuid
from typing import Any, Sequence

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.responses import Response

logger = logging.getLogger("roam.api")


def getRequestId(request: Request) -> str:
    return getattr(request.state, "requestId", None) or str(uuid.uuid4())


def addSecurityHeaders(response: Response) -> None:
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none';"


def addCorsHeaders(response: Response, origin: str | None, allowOrigins: Sequence[str]) -> None:
    if origin and origin in allowOrigins:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"


def logHttpError(
    request: Request,
    *,
    requestId: str,
    statusCode: int,
    detail: Any,
    cause: str | None = None,
) -> None:
    extra: dict[str, Any] = {
        "requestId": requestId,
        "path": request.url.path,
        "method": request.method,
        "status": statusCode,
        "detail": detail,
    }
    if cause:
        extra["cause"] = cause
    logger.warning("http_error", extra=extra)


def buildJsonErrorResponse(
    request: Request,
    *,
    requestId: str,
    origin: str | None,
    statusCode: int,
    detail: Any,
    allowOrigins: Sequence[str],
    log: bool = True,
    cause: str | None = None,
) -> JSONResponse:
    if log:
        logHttpError(request, requestId=requestId, statusCode=statusCode, detail=detail, cause=cause)
    response = JSONResponse(status_code=statusCode, content={"detail": detail})
    response.headers["X-Request-Id"] = requestId
    addSecurityHeaders(response)
    addCorsHeaders(response, origin, allowOrigins)
    return response
