"""
Auth and path policy for the rate limiter middleware.

Path exemptions: which routes skip Firebase auth or allow unverified email.
Verification rule: defense in depth so new API paths do not accidentally skip
email verification.

When adding public routes or signup/verify flows, update this module so the
middleware stays in sync with the API surface.
"""

from __future__ import annotations

from typing import Any

from app.common.backendErrors import Forbidden

# Token-backed routes under this prefix skip Firebase auth in middleware (public share links).
shareApiPrefix = "/api/share/"

# Exact paths that skip Firebase auth entirely (public or pre-auth).
authExemptExactPaths: frozenset[str] = frozenset(
    {
        "/health",
        "/docs",
        "/openapi.json",
        "/redoc",
        "/api/users/check-username",
    }
)

# Authenticated routes where an unverified email is still allowed (signup / verify flow).
verifyExemptPaths: frozenset[str] = frozenset(
    {
        "/api/users",
        "/api/users/verify",
    }
)


def isAuthExemptPath(path: str) -> bool:
    if path.startswith(shareApiPrefix):
        return True
    return path in authExemptExactPaths


def isVerificationExemptPath(path: str) -> bool:
    return path in verifyExemptPaths


def enforceEmailVerifiedIfRequired(
    decodedToken: dict[str, Any],
    path: str,
    trustedAuthProviders: set[str],
) -> None:
    """
    Require verified email for this path unless the path is verification-exempt
    or the sign-in provider is trusted (see TRUSTED_AUTH_PROVIDERS).
    """
    if isVerificationExemptPath(path):
        return
    emailVerified = bool(decodedToken.get("email_verified"))
    signInProvider = (
        decodedToken.get("firebase", {}).get("sign_in_provider")
        if isinstance(decodedToken.get("firebase"), dict)
        else None
    )
    if not emailVerified and signInProvider not in trustedAuthProviders:
        raise Forbidden("Email not verified")
