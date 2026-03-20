#!/usr/bin/env bash
# check_openapi_swift.sh — Does NOT talk to FastAPI. Re-normalizes contracts/openapi.json
# and runs swift build. Use export_openapi.sh when the API changed in Python.
# Local: ensure normalized spec + RoamOpenAPI package compile.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/normalize_openapi_for_swift.py" "$ROOT/contracts/openapi.json" "$ROOT/RoamOpenAPI/Sources/RoamOpenAPI/openapi.yaml"
cd "$ROOT/RoamOpenAPI"
swift build
