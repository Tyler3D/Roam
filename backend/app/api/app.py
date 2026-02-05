import logging
import time
import uuid
from typing import Callable

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.users import usersRouter
from app.auth.auth import getBearerToken, verifyFirebaseTokenString
from app.common.config import IS_DEV, getTrustedAuthProviders


app = FastAPI(title="Cozy Corner Dates API")

isDev = IS_DEV()
if not isDev:
    raise RuntimeError("Only 'dev' environment is supported right now.")

allowOrigins = ["http://localhost:3000"] if isDev else [""]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowOrigins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


rateLimitWindowSeconds = 60
rateLimitMaxRequests = 120
rateLimitStore: dict[str, list[float]] = {}

logger = logging.getLogger("cozy.api")
authFailureWindowSeconds = 900
authFailureMaxAttempts = 5
authLockoutSeconds = 900
authFailureStore: dict[str, list[float]] = {}
authLockoutUntil: dict[str, float] = {}
trustedAuthProviders = getTrustedAuthProviders()


def _isAuthExemptPath(path: str) -> bool:
    return path in {"/health", "/docs", "/openapi.json", "/redoc"}


def _isVerificationExemptPath(path: str) -> bool:
    return path in {"/api/users", "/api/users/verify"}


def _addSecurityHeaders(response: JSONResponse) -> None:
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none';"


def _addCorsHeaders(response: JSONResponse, origin: str | None) -> None:
    if origin and origin in allowOrigins:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"


@app.middleware("http")
async def authAndRateLimitMiddleware(request: Request, callNext: Callable):
    now = time.time()
    path = request.url.path
    origin = request.headers.get("Origin")
    requestId = request.headers.get("X-Request-Id") or str(uuid.uuid4())
    request.state.requestId = requestId
    startTime = time.time()
    if request.method == "OPTIONS":
        response = await callNext(request)
        response.headers["X-Request-Id"] = requestId
        _addSecurityHeaders(response)
        _addCorsHeaders(response, origin)
        return response
    clientIp = request.client.host if request.client else "unknown"
    authKey = f"ip:{clientIp}"
    lockoutUntil = authLockoutUntil.get(authKey)
    if lockoutUntil and now < lockoutUntil:
        response = JSONResponse(
            status_code=429,
            content={"detail": "Too many failed auth attempts"},
        )
        response.headers["X-Request-Id"] = requestId
        _addSecurityHeaders(response)
        _addCorsHeaders(response, origin)
        return response
    if not _isAuthExemptPath(path):
        try:
            authorization = request.headers.get("Authorization")
            token = getBearerToken(authorization)
            decodedToken = verifyFirebaseTokenString(token)
            request.state.decodedToken = decodedToken
            emailVerified = bool(decodedToken.get("email_verified"))
            signInProvider = (
                decodedToken.get("firebase", {}).get("sign_in_provider")
                if isinstance(decodedToken.get("firebase"), dict)
                else None
            )
            if (
                not _isVerificationExemptPath(path)
                and not emailVerified
                and signInProvider not in trustedAuthProviders
            ):
                response = JSONResponse(
                    status_code=403,
                    content={"detail": "Email not verified"},
                )
                response.headers["X-Request-Id"] = requestId
                _addSecurityHeaders(response)
                _addCorsHeaders(response, origin)
                return response
            key = f"uid:{decodedToken.get('uid')}"
        except Exception as exc:
            failureTimestamps = authFailureStore.get(authKey, [])
            failureWindowStart = now - authFailureWindowSeconds
            failureTimestamps = [ts for ts in failureTimestamps if ts >= failureWindowStart]
            failureTimestamps.append(now)
            authFailureStore[authKey] = failureTimestamps
            if len(failureTimestamps) >= authFailureMaxAttempts:
                authLockoutUntil[authKey] = now + authLockoutSeconds
            response = JSONResponse(status_code=401, content={"detail": "Unauthorized"})
            response.headers["X-Request-Id"] = requestId
            _addSecurityHeaders(response)
            _addCorsHeaders(response, origin)
            logger.warning(
                "auth_failed",
                extra={
                    "requestId": requestId,
                    "path": path,
                    "method": request.method,
                    "status": 401,
                    "error": str(exc),
                },
            )
            return response
    else:
        key = f"ip:{clientIp}"

    timestamps = rateLimitStore.get(key, [])
    windowStart = now - rateLimitWindowSeconds
    timestamps = [ts for ts in timestamps if ts >= windowStart]
    if len(timestamps) >= rateLimitMaxRequests:
        response = JSONResponse(status_code=429, content={"detail": "Rate limit exceeded"})
        response.headers["X-Request-Id"] = requestId
        _addSecurityHeaders(response)
        _addCorsHeaders(response, origin)
        logger.warning(
            "rate_limited",
            extra={
                "requestId": requestId,
                "path": path,
                "method": request.method,
                "status": 429,
            },
        )
        return response
    timestamps.append(now)
    rateLimitStore[key] = timestamps

    response = await callNext(request)
    response.headers["X-Request-Id"] = requestId
    _addSecurityHeaders(response)
    _addCorsHeaders(response, origin)
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


@app.get("/health")
def healthCheck() -> dict:
    return {"status": "ok"}


app.include_router(usersRouter, prefix="/api")

