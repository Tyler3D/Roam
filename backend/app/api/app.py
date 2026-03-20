import logging

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
from app.api.tasks import tasksRouter
from app.common.config import getCorsAllowOrigins
from app.middleware.utils import (
    addCorsHeaders,
    addSecurityHeaders,
    buildJsonErrorResponse,
    getRequestId,
    logHttpError,
)
from app.middleware.rateLimiter import rateLimiterMiddleware

logger = logging.getLogger("roam.api")
app = FastAPI(title="Roam API")

allowOrigins = tuple(getCorsAllowOrigins())


@app.exception_handler(FastAPIHTTPException)
async def httpExceptionHandler(request: Request, exc: FastAPIHTTPException) -> JSONResponse:
    """Log HTTPException from routes/dependencies and return consistent JSON."""
    requestId = getRequestId(request)
    cause = str(exc.__cause__) if exc.__cause__ else None
    logHttpError(
        request,
        requestId=requestId,
        statusCode=exc.status_code,
        detail=exc.detail,
        cause=cause,
    )
    return buildJsonErrorResponse(
        request,
        requestId=requestId,
        origin=request.headers.get("Origin"),
        statusCode=exc.status_code,
        detail=exc.detail,
        allowOrigins=allowOrigins,
        log=False,
    )


@app.exception_handler(Exception)
async def unhandledExceptionHandler(request: Request, exc: Exception) -> JSONResponse:
    """Log unhandled exceptions (500) and return a generic response."""
    requestId = getRequestId(request)
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
    addSecurityHeaders(response)
    addCorsHeaders(response, request.headers.get("Origin"), allowOrigins)
    return response


app.add_middleware(
    CORSMiddleware,
    allow_origins=list(allowOrigins),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.middleware("http")(rateLimiterMiddleware)


@app.on_event("startup")
def startup():
    logger.info("Roam API started")


@app.get("/health")
def healthCheck() -> dict:
    return {"status": "ok"}


app.include_router(usersRouter, prefix="/api")
app.include_router(ingestRouter, prefix="/api")
app.include_router(ideasRouter, prefix="/api")
app.include_router(plansRouter, prefix="/api")
app.include_router(tasksRouter, prefix="/api")
app.include_router(placesRouter, prefix="/api")
app.include_router(friendsRouter, prefix="/api")
app.include_router(shareRouter, prefix="/api")
app.include_router(notificationsRouter, prefix="/api")
