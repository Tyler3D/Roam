#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"

if [ -f "${BACKEND_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${BACKEND_DIR}/.env"
  set +a
fi

pip install -r "${BACKEND_DIR}/requirements.txt"

exec uvicorn app.main:app --reload --app-dir "${BACKEND_DIR}"

