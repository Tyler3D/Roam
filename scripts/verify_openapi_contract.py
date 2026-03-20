#!/usr/bin/env python3
"""
Exit 0 if FastAPI's live OpenAPI dict matches contracts/openapi.json.
Used in CI so API changes require running scripts/export_openapi.sh and committing artifacts.

Needs importable backend: set ENVIRONMENT=dev and a dummy DATABASE_URL (see workflow).
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "contracts" / "openapi.json"


def main() -> None:
    if not CONTRACT.is_file():
        print(f"Missing {CONTRACT.relative_to(ROOT)}", file=sys.stderr)
        sys.exit(2)

    backend = ROOT / "backend"
    sys.path.insert(0, str(backend))
    os.chdir(backend)

    from app.api.app import app  # noqa: E402

    fresh = app.openapi()
    committed = json.loads(CONTRACT.read_text(encoding="utf-8"))

    if fresh == committed:
        print("OpenAPI contract matches FastAPI app.")
        return

    print(
        "contracts/openapi.json is out of date with the FastAPI app.\n"
        "From the repo root, run:\n"
        "  ./scripts/export_openapi.sh\n"
        "Then commit contracts/openapi.json and RoamOpenAPI/Sources/RoamOpenAPI/openapi.yaml\n"
        "(and regenerate frontend types if you use them: cd frontend && npm run generate:api:file)",
        file=sys.stderr,
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
