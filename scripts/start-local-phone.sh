#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_NAME="${CONTAINER_NAME:-cozy-postgres}"
POSTGRES_USER="${POSTGRES_USER:-admin}"
POSTGRES_DB="${POSTGRES_DB:-cozycorner}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"

BACKEND_ENV_FILE="${ROOT}/backend/.env"
SCHEMA_FILE="${ROOT}/sql/schema.sql"

if [[ ! -f "${BACKEND_ENV_FILE}" ]]; then
  cat >&2 <<EOF
Missing backend env file: ${BACKEND_ENV_FILE}

Create it from backend/env.template, then rerun this script.
EOF
  exit 1
fi

if [[ ! -f "${SCHEMA_FILE}" ]]; then
  echo "Missing schema file: ${SCHEMA_FILE}" >&2
  exit 1
fi

echo "[1/3] Starting local Postgres container..."
bash "${ROOT}/scripts/start-postgres.sh"

echo "[2/3] Waiting for Postgres to accept connections..."
for _ in {1..30}; do
  if docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
  echo "Postgres did not become ready in time." >&2
  exit 2
fi

echo "[3/3] Applying schema (idempotent) to ${POSTGRES_DB}..."
docker exec -i "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" < "${SCHEMA_FILE}" >/dev/null

# Pick a likely LAN IPv4 so users can point iPhone app to this Mac.
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"

if [[ -n "${LAN_IP}" ]]; then
  cat <<EOF

Local stack is up.
For iPhone testing, set iOS base URL to: http://${LAN_IP}:${PORT}
Then run the app on device from Xcode.
EOF
else
  cat <<EOF

Local stack is up.
Could not auto-detect LAN IP. Run one of:
  ipconfig getifaddr en0
  ipconfig getifaddr en1
Then set iOS base URL to: http://<that-ip>:${PORT}
EOF
fi

HOST="${HOST}" PORT="${PORT}" bash "${ROOT}/scripts/start-backend.sh"
