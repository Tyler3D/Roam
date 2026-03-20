#!/usr/bin/env bash
# export_openapi.sh — Full refresh from Python: openapi.json + RoamOpenAPI/openapi.yaml.
# (Transformer-only step lives in normalize_openapi_for_swift.py; optional verify: check_openapi_swift.sh.)
# Regenerate contracts/openapi.json from the FastAPI app (same schema the backend serves at /openapi.json).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/backend"
if [[ ! -d .venv-export ]]; then
  echo "Create .venv-export with Python 3.12+ and: pip install -r requirements.txt" >&2
  echo "  Example: python3.12 -m venv .venv-export && . .venv-export/bin/activate && pip install -r requirements.txt" >&2
  exit 1
fi
# shellcheck disable=SC1091
source .venv-export/bin/activate
python3 - <<'PY'
import json, sys
sys.path.insert(0, ".")
from app.api.app import app
spec = app.openapi()
with open("../contracts/openapi.json", "w") as f:
    json.dump(spec, f, indent=2)
print("Wrote ../contracts/openapi.json")
PY
# Swift codegen: flatten Pydantic anyOf+null and OpenAPI 3.0.3 (see scripts/normalize_openapi_for_swift.py).
python3 "$ROOT/scripts/normalize_openapi_for_swift.py" "$ROOT/contracts/openapi.json" "$ROOT/RoamOpenAPI/Sources/RoamOpenAPI/openapi.yaml"
echo "Frontend: (cd frontend && npm run generate:api:file)"
echo "Swift: (cd RoamOpenAPI && swift build)"
