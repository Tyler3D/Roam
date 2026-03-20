# OpenAPI integration (web ↔ FastAPI)

How the **TypeScript web app** stays aligned with the **FastAPI** JSON API using **OpenAPI** as the contract. This is separate from the **Google Cloud API Gateway** OpenAPI config used to route public traffic to Cloud Run ([ARCHITECTURE.md](ARCHITECTURE.md)); that gateway spec describes infrastructure, not the typings in this repo.

---

## Source of truth (backend)

**FastAPI** exposes a machine-readable schema at **`GET /openapi.json`** on the running API (default FastAPI behavior). Pydantic models, route decorators, and response types on the backend determine `paths`, `components.schemas`, and operation shapes.

- **Local:** `http://localhost:8000/openapi.json` (or whatever host/port you use).
- **Prod:** same path on the deployed API base URL if you need to diff against a running revision.

There is no checked-in “golden” `openapi.json` in this repo today; regeneration assumes you can reach a running backend (or you save a snapshot yourself and use the file-based script below).

---

## Code generation (frontend)

Tool: **[openapi-typescript](https://github.com/drwpow/openapi-typescript)** (v7 in `frontend/package.json`).

| Script | Command | Use when |
|--------|---------|----------|
| `generate:api` | `openapi-typescript http://localhost:8000/openapi.json --enum -o src/models/generated/api.d.ts` | Backend is running locally on port **8000**. |
| `generate:api:file` | `openapi-typescript scripts/openapi.json --enum -o src/models/generated/api.d.ts` | You have saved a copy of the spec at `frontend/scripts/openapi.json` (create the file/dir if you use this). |

The **`--enum`** flag emits string-literal unions / enums for Pydantic enums so shared values (e.g. idea status) match the server.

**Output:** `frontend/src/models/generated/api.d.ts` — **do not edit by hand**; it is overwritten on each run.

---

## How generated types are used

The generated file exports:

- **`paths`** — per-path, per-method request/response typings (`operations[...]`).
- **`components["schemas"]`** — shared DTOs (`UserRead`, `PlanRead`, `IdeaCreate`, etc.).

The app does **not** import `api.d.ts` everywhere directly. Thin modules under `frontend/src/models/` re-export the pieces the UI needs, for example:

- `components["schemas"]["IdeaRead"]` → `Idea` in `models/idea.ts`
- `components["schemas"]["PlanRead"]` → `Plan` in `models/plan.ts`

That keeps imports stable and documents that those types are **API-shaped** (snake_case in JSON is still whatever the backend emits; naming in TS follows the generated schema).

---

## What stays hand-written

- **HTTP client:** `frontend/src/lib/api.ts` uses `fetch`, builds URLs from `VITE_API_BASE_URL`, and attaches **Firebase** + **`X-Roam-Authorization`** headers. Paths and methods are plain strings (e.g. `"/api/me"`). They should match `paths` in the OpenAPI doc; changing the API without regenerating types can cause drift.
- **No generated SDK:** There is no openapi-fetch or orval client in the tree—only **types**.

---

## Regeneration checklist

1. Start the backend with the schema you want reflected.
2. From `frontend/`: `npm run generate:api`.
3. Review the diff to `api.d.ts` (and fix any broken re-exports in `models/*.ts` if schema names changed).
4. Commit the updated `api.d.ts` (and model tweaks) with the backend change that caused them.

---

## Related docs

| Doc | Purpose |
|-----|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Runtime topology; API Gateway vs FastAPI |
| [ERD.md](ERD.md) | Database entities (orthogonal to OpenAPI DTOs) |
