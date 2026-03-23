from __future__ import annotations

import time
from typing import Any, Callable

from app.services.interpret import interpret_idea
from app.services.interpret_validation import validate_interpret_output


StepFn = Callable[[], Any]


def _run_step(steps: list[dict[str, Any]], name: str, fn: StepFn) -> Any:
    start = time.perf_counter()
    try:
        output = fn()
        steps.append(
            {
                "name": name,
                "status": "ok",
                "durationMs": int((time.perf_counter() - start) * 1000),
            }
        )
        return output
    except Exception as exc:
        steps.append(
            {
                "name": name,
                "status": "error",
                "durationMs": int((time.perf_counter() - start) * 1000),
                "errorCode": type(exc).__name__,
            }
        )
        raise


def run_interpret_orchestration(
    *,
    raw_input: str,
    resolve_invitees: Callable[[list[str]], list[dict[str, Any]]] | None = None,
) -> dict[str, Any]:
    steps: list[dict[str, Any]] = []

    interpreted = _run_step(steps, "interpret_scribble", lambda: interpret_idea(raw_input))
    validation = _run_step(
        steps, "validate_output", lambda: validate_interpret_output(interpreted)
    )
    result = dict(validation.normalized)

    invitees = result.get("invitees") or []
    resolved: list[dict[str, Any]] = []
    if invitees and resolve_invitees is not None:
        resolved = _run_step(steps, "resolve_invitees", lambda: resolve_invitees(invitees))
    else:
        steps.append({"name": "resolve_invitees", "status": "skipped", "durationMs": 0})

    # Placeholder step marker so clients can show consistent rails.
    steps.append({"name": "search_places", "status": "deferred", "durationMs": 0})

    result["orchestrationVersion"] = "v1"
    result["steps"] = steps
    if resolved:
        result["resolvedInvitees"] = resolved
        has_ambiguous = any(not r.get("userId") for r in resolved)
        uncertainty = dict(result.get("uncertainty") or {})
        flags = dict(uncertainty.get("flags") or {})
        flags["inviteesAmbiguous"] = flags.get("inviteesAmbiguous", False) or has_ambiguous
        uncertainty["flags"] = flags
        uncertainty["requiresConfirmation"] = bool(uncertainty.get("requiresConfirmation")) or has_ambiguous
        result["uncertainty"] = uncertainty

    uncertainty = result.get("uncertainty") or {}
    flags = uncertainty.get("flags") or {}
    if flags.get("inviteesAmbiguous"):
        result["inviteesProposed"] = result.get("invitees", [])
        result["invitees"] = []
        result["inviteesConfirmed"] = False
    else:
        result["inviteesConfirmed"] = True

    if flags.get("taskAssignmentsAmbiguous"):
        result["taskAssignmentsProposed"] = result.get("taskAssignments")
        result["taskAssignments"] = None
        result["taskAssignmentsConfirmed"] = False
    else:
        result["taskAssignmentsConfirmed"] = True

    return result
