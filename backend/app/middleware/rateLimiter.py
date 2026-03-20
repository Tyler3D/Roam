"""
Firebase auth gate, email-verification policy, and in-memory rate limits.

HTTP errors are returned as JSON via `middleware.utils` (middleware cannot rely
on FastAPI exception handlers for HTTPException).
"""

from __future__ import annotations

import logging
import time
import uuid
from typing import Awaitable, Callable

from fastapi import Request
from fastapi.exceptions import HTTPException as FastAPIHTTPException
from starlette.responses import Response

from app.auth.auth import getBearerToken, verifyFirebaseTokenString
from app.common.config import getCorsAllowOrigins, getTrustedAuthProviders

from .policy import enforceEmailVerifiedIfRequired, isAuthExemptPath
from .utils import addCorsHeaders, addSecurityHeaders, buildJsonErrorResponse

logger = logging.getLogger("roam.api")

allowOrigins = tuple(getCorsAllowOrigins())
trustedAuthProviders = getTrustedAuthProviders()

rateLimitWindowSeconds = 60
rateLimitMaxRequests = 120
rateLimitStore: dict[str, list[float]] = {}

authFailureWindowSeconds = 900
authFailureMaxAttempts = 5
authLockoutSeconds = 900
authFailureStore: dict[str, list[float]] = {}
authLockoutUntil: dict[str, float] = {}


def _getClientIdentity(request: Request) -> str:
    """
    Prefer X-Forwarded-For (leftmost = original client when proxies append).
    On Cloud Run / behind API Gateway, request.client is often an internal hop,
    so forwarded-for is needed for per-client rate limits and lockouts.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        first = forwarded.split(",")[0].strip()
        if first:
            return first
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def _middlewareError(
    request: Request,
    *,
    requestId: str,
    origin: str | None,
    statusCode: int,
    detail: str,
) -> Response:
    return buildJsonErrorResponse(
        request,
        requestId=requestId,
        origin=origin,
        statusCode=statusCode,
        detail=detail,
        allowOrigins=allowOrigins,
    )


async def rateLimiterMiddleware(
    request: Request, callNext: Callable[[Request], Awaitable[Response]]
) -> Response:
    now = time.time()
    path = request.url.path
    origin = request.headers.get("Origin")
    requestId = request.headers.get("X-Request-Id") or str(uuid.uuid4())
    request.state.requestId = requestId
    startTime = now

    if request.method == "OPTIONS":
        response = await callNext(request)
        response.headers["X-Request-Id"] = requestId
        addSecurityHeaders(response)
        addCorsHeaders(response, origin, allowOrigins)
        return response

    clientId = _getClientIdentity(request)
    authKey = f"client:{clientId}"
    lockoutUntil = authLockoutUntil.get(authKey)
    if lockoutUntil and now < lockoutUntil:
        return _middlewareError(
            request,
            requestId=requestId,
            origin=origin,
            statusCode=429,
            detail="Too many failed auth attempts",
        )

    if not isAuthExemptPath(path):
        try:
            authorization = request.headers.get("Authorization")
            token = getBearerToken(authorization)
            decodedToken = verifyFirebaseTokenString(token)
            request.state.decodedToken = decodedToken
            enforceEmailVerifiedIfRequired(decodedToken, path, trustedAuthProviders)
            key = f"uid:{decodedToken.get('uid')}"
        except FastAPIHTTPException as exc:
            if exc.status_code == 403:
                detailStr: str = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
                return _middlewareError(
                    request,
                    requestId=requestId,
                    origin=origin,
                    statusCode=exc.status_code,
                    detail=detailStr,
                )
            if exc.status_code != 401:
                raise
            detailStr = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
            failureTimestamps = authFailureStore.get(authKey, [])
            failureWindowStart = now - authFailureWindowSeconds
            failureTimestamps = [ts for ts in failureTimestamps if ts >= failureWindowStart]
            failureTimestamps.append(now)
            authFailureStore[authKey] = failureTimestamps
            if len(failureTimestamps) >= authFailureMaxAttempts:
                authLockoutUntil[authKey] = now + authLockoutSeconds
            return _middlewareError(
                request,
                requestId=requestId,
                origin=origin,
                statusCode=401,
                detail=detailStr,
            )
        except Exception:
            logger.exception(
                "middleware_auth_error",
                extra={"requestId": requestId, "path": path, "method": request.method},
            )
            return _middlewareError(
                request,
                requestId=requestId,
                origin=origin,
                statusCode=500,
                detail="Internal server error",
            )
    else:
        key = f"client:{clientId}"

    timestamps = rateLimitStore.get(key, [])
    windowStart = now - rateLimitWindowSeconds
    timestamps = [ts for ts in timestamps if ts >= windowStart]
    if len(timestamps) >= rateLimitMaxRequests:
        return _middlewareError(
            request,
            requestId=requestId,
            origin=origin,
            statusCode=429,
            detail="Rate limit exceeded",
        )
    timestamps.append(now)
    rateLimitStore[key] = timestamps

    response = await callNext(request)
    response.headers["X-Request-Id"] = requestId
    addSecurityHeaders(response)
    addCorsHeaders(response, origin, allowOrigins)
    durationMs = int((time.time() - startTime) * 1000)
    logger.info(
        "request",
        extra={
            "requestId": requestId,
            "path": path,
            "method": request.method,
            "status": response.status_code,
            "durationMs": durationMs,
        },
    )
    return response
