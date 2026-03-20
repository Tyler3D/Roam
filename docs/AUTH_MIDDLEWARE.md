# Auth and HTTP middleware

This document describes how authentication, email verification, and rate limiting are applied before requests reach route handlers. Code lives under [`backend/app/middleware/`](../backend/app/middleware/):

- [`rateLimiter.py`](../backend/app/middleware/rateLimiter.py) — main middleware (auth, verification, rate limits)
- [`policy.py`](../backend/app/middleware/policy.py) — exempt paths and `enforceEmailVerifiedIfRequired`
- [`utils.py`](../backend/app/middleware/utils.py) — shared response headers, JSON errors, logging (also used by global exception handlers in `app.py`)

## Order of processing

1. **Uvicorn** may apply `ProxyHeadersMiddleware` so `X-Forwarded-For` is visible to the app.
2. **CORSMiddleware** (Starlette) handles CORS for normal responses.
3. **`rateLimiterMiddleware`** runs next: assigns `request.state.requestId`, handles `OPTIONS`, enforces auth/verification/rate limits, then calls the route.
4. **Route** runs; dependencies such as `getCurrentAuth` read `request.state.decodedToken` set by the middleware.

Errors raised inside this HTTP middleware are **not** reliably handled by FastAPI’s `@app.exception_handler` for `HTTPException`. The middleware therefore returns **`JSONResponse`** via [`utils.buildJsonErrorResponse`](../backend/app/middleware/utils.py). Route-level errors still use the global exception handlers in [`app.py`](../backend/app/api/app.py).

## `request.state` contract

| Field           | Set by              | Meaning |
|----------------|---------------------|---------|
| `requestId`    | Middleware          | Correlation id; echoed as `X-Request-Id`. |
| `decodedToken` | Middleware          | Firebase ID token claims dict, only for non-exempt paths after successful verification. |

`getDecodedTokenFromRequest` in [`auth.py`](../backend/app/auth/auth.py) expects `decodedToken` for protected routes. If middleware is bypassed or mis-ordered, routes may see `Unauthorized("Missing auth")`.

## Route policy (update when adding routes)

- **`authExemptExactPaths`** and **`shareApiPrefix`** — no Firebase token required.
- **`verifyExemptPaths`** — token required, but **unverified email** is allowed (signup and email verification endpoints).

Edit [`policy.py`](../backend/app/middleware/policy.py) when you add public or pre-verify API paths.

## Email verification (middleware vs routes)

Middleware calls **`enforceEmailVerifiedIfRequired`** ([`policy.py`](../backend/app/middleware/policy.py)) for every authenticated, non-exempt path. That is the default safety net so new endpoints do not accidentally allow unverified users.

Certain routes (e.g. `POST /api/users/verify`) may still perform **additional** checks (e.g. that Firebase now reports `email_verified`) because middleware deliberately **exempts** those paths from the global rule.

## Client identity for rate limits

Rate limiting and auth lockout use **`client:{identity}`** where identity is preferentially the **first** address in **`X-Forwarded-For`**, else `request.client.host`. On Cloud Run behind Google’s edge, the direct `request.client` address is often internal; forwarded-for reflects the end client when the platform sets it. See also [ARCHITECTURE.md](ARCHITECTURE.md) (API Gateway → Cloud Run).

## HTTP status codes from middleware

| Status | Typical cause |
|--------|----------------|
| 401    | Missing/invalid Bearer token, or invalid Firebase token. |
| 403    | Authenticated but email not verified (non-exempt path, non-trusted provider). |
| 429    | Per-key rate limit exceeded, or auth failure lockout window active. |
