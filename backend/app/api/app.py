import logging
import time
import uuid
from typing import Callable

from fastapi import FastAPI, Request
from fastapi.exceptions import HTTPException as FastAPIHTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.ingest import ingestRouter
from app.api.users import usersRouter
from app.api.ideas import ideasRouter
from app.api.plans import plansRouter
from app.api.places import placesRouter
from app.api.friends import friendsRouter
from app.api.share import shareRouter
from app.api.notifications import notificationsRouter
from app.auth.auth import getBearerToken, verifyFirebaseTokenString
from app.common.backendErrors import Forbidden, RateLimited, Unauthorized
from app.common.config import IS_DEV, getTrustedAuthProviders

logger = logging.getLogger("roam.api")
app = FastAPI(title="Roam API")


def _getRequestId(request: Request) -> str:
    return getattr(request.state, "requestId", None) or str(uuid.uuid4())


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


@app.exception_handler(FastAPIHTTPException)
async def httpExceptionHandler(request: Request, exc: FastAPIHTTPException) -> JSONResponse:
    """Log all 4xx/5xx from HTTPException and return a consistent JSON response."""
    requestId = _getRequestId(request)
    cause = exc.__cause__
    logger.warning(
        "http_error",
        extra={
            "requestId": requestId,
            "path": request.url.path,
            "method": request.method,
            "status": exc.status_code,
            "detail": exc.detail,
            **({"cause": str(cause)} if cause else {}),
        },
    )
    response = JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
    response.headers["X-Request-Id"] = requestId
    _addSecurityHeaders(response)
    _addCorsHeaders(response, request.headers.get("Origin"))
    return response


@app.exception_handler(Exception)
async def unhandledExceptionHandler(request: Request, exc: Exception) -> JSONResponse:
    """Log unhandled exceptions (500) and return a generic response."""
    requestId = _getRequestId(request)
    logger.exception(
        "unhandled_exception",
        extra={
            "requestId": requestId,
            "path": request.url.path,
            "method": request.method,
        },
    )
    response = JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )
    response.headers["X-Request-Id"] = requestId
    _addSecurityHeaders(response)
    _addCorsHeaders(response, request.headers.get("Origin"))
    return response

isDev = IS_DEV()
allowOrigins = ["http://localhost:3000"] if isDev else ["https://roam-alpha.web.app", "https://roam-alpha.firebaseapp.com"]

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

authFailureWindowSeconds = 900
authFailureMaxAttempts = 5
authLockoutSeconds = 900
authFailureStore: dict[str, list[float]] = {}
authLockoutUntil: dict[str, float] = {}
trustedAuthProviders = getTrustedAuthProviders()


def _isAuthExemptPath(path: str) -> bool:
    if path.startswith("/api/share/"):
        return True
    return path in {
        "/health",
        "/docs",
        "/openapi.json",
        "/redoc",
    }


def _isVerificationExemptPath(path: str) -> bool:
    return path in {"/api/users", "/api/users/verify"}


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
        raise RateLimited("Too many failed auth attempts")
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
                raise Forbidden("Email not verified")
            key = f"uid:{decodedToken.get('uid')}"
        except Exception:
            failureTimestamps = authFailureStore.get(authKey, [])
            failureWindowStart = now - authFailureWindowSeconds
            failureTimestamps = [ts for ts in failureTimestamps if ts >= failureWindowStart]
            failureTimestamps.append(now)
            authFailureStore[authKey] = failureTimestamps
            if len(failureTimestamps) >= authFailureMaxAttempts:
                authLockoutUntil[authKey] = now + authLockoutSeconds
            raise Unauthorized("Unauthorized")
    else:
        key = f"ip:{clientIp}"

    timestamps = rateLimitStore.get(key, [])
    windowStart = now - rateLimitWindowSeconds
    timestamps = [ts for ts in timestamps if ts >= windowStart]
    if len(timestamps) >= rateLimitMaxRequests:
        raise RateLimited("Rate limit exceeded")
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
app.include_router(ingestRouter, prefix="/api")
app.include_router(ideasRouter, prefix="/api")
app.include_router(plansRouter, prefix="/api")
app.include_router(placesRouter, prefix="/api")
app.include_router(friendsRouter, prefix="/api")
app.include_router(shareRouter, prefix="/api")
app.include_router(notificationsRouter, prefix="/api")

