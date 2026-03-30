#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"

# Do not source backend/.env in the shell: complex JSON secrets (for example
# FIREBASE_SERVICE_ACCOUNT_JSON) can be transformed by shell parsing and break
# runtime JSON decoding. The app loads backend/.env via python-dotenv.

pip install -r "${BACKEND_DIR}/requirements.txt"

existing_listener="$(lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
if [ -n "${existing_listener}" ]; then
	listener_cmd="$(ps -p "${existing_listener}" -o command= 2>/dev/null || true)"
	if echo "${listener_cmd}" | grep -q "uvicorn app.main:app"; then
		echo "Roam backend already running on ${HOST}:${PORT} (pid ${existing_listener})."
		echo "Health: http://${HOST}:${PORT}/health"
		exit 0
	fi

	echo "Port ${PORT} is already in use by pid ${existing_listener}."
	echo "Command: ${listener_cmd}"
	echo "Stop that process or run with a different port, e.g. PORT=8001 bash scripts/start-backend.sh"
	exit 1
fi

exec uvicorn app.main:app --reload --app-dir "${BACKEND_DIR}" --host "${HOST}" --port "${PORT}"

