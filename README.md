# Roam (Full Stack)

Roam is a full-stack app with:

- `frontend/`: React + Vite web client (Firebase Auth)
- `backend/`: FastAPI API server (Python)
- `infra/` + `scripts/start-postgres.sh`: local Postgres in Docker

## Prerequisites

- Docker Desktop
- Node.js + npm
- Python 3.11 (recommended)

## Environment Files

- Backend env: `backend/.env`
- Frontend env: `frontend/.env`

## Run Locally (Recommended Order)

### 1) Start Postgres (Docker)

Ensure Docker Desktop is running, then run the following from the repository root:

```bash
./scripts/start-postgres.sh
```

This starts a Postgres container on `localhost:5432` with db `cozycorner`.

### 2) Start Backend (FastAPI)

From repo root:

```bash
python3.11 -m venv .venv311
source .venv311/bin/activate
python -m pip install -r backend/requirements.txt
python -m uvicorn app.main:app --reload --app-dir backend
```

Backend default URL: `http://127.0.0.1:8000`  
Health check: `http://127.0.0.1:8000/health`

If port `8000` is busy, run:

```bash
python -m uvicorn app.main:app --reload --app-dir backend --port 8001
```

### 3) Start Frontend (Vite)

In a second terminal:

```bash
cd frontend
npm install
npm run dev
```

Frontend URL: `http://localhost:3000`

## Important Local Notes

- Start Postgres first, or backend endpoints that hit DB will fail.
- If backend runs on a non-default port (for example `8001`), set:
  - `frontend/.env` -> `VITE_API_BASE_URL=http://localhost:8001`
  - then restart `npm run dev`.
- If `pip` is not available globally, use `python -m pip ...` inside the venv.

