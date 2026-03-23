# Backend environment variables

Used by the Roam API (FastAPI) when running locally or on Cloud Run.

## Required

| Variable                  | Description                                                                 |
| ------------------------- | --------------------------------------------------------------------------- |
| `ENVIRONMENT`             | `dev` or `prod`.                                                            |
| `DATABASE_URL`            | PostgreSQL connection URL (e.g. `postgresql://user:pass@host:5432/dbname`). |
| `GEMINI_API_KEY`          | Google Gemini API key for idea interpretation and reel vision processing.   |
| `FIREBASE_PROJECT_ID`     | Firebase project ID for token verification.                                 |
| `FIREBASE_PRIVATE_KEY_ID` | Firebase service account private key ID.                                    |
| `FIREBASE_PRIVATE_KEY`    | Firebase service account private key (escape newlines as `\n`).             |
| `FIREBASE_CLIENT_EMAIL`   | Firebase service account client email.                                      |

## Optional

| Variable                   | Description                                                                                                                                                                                                                                                                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GEMINI_MODEL`             | Gemini model name (default: `gemini-2.5-flash`). Used for scribble interpret and reel vision.                                                                                                                                                                                                                                              |
| `CORS_ORIGINS`             | Comma-separated allowed origins in prod (e.g. `https://app.example.com,https://www.example.com`). If unset, `FRONTEND_ORIGIN` is used.                                                                                                                                                                                                     |
| `FRONTEND_ORIGIN`          | Single allowed origin in prod. Ignored if `CORS_ORIGINS` is set.                                                                                                                                                                                                                                                                           |
| `TRUSTED_AUTH_PROVIDERS`   | Comma-separated Firebase sign-in providers that skip email verification (default: `google.com,password`).                                                                                                                                                                                                                                  |
| `GOOGLE_MAPS_API_KEY`      | Google Maps Places API key for resolving place addresses. If unset, ingestion still runs but places are not geocoded.                                                                                                                                                                                                                      |
| `INTERPRET_ORCHESTRATION_ENABLED` | Feature flag for scribble orchestration path in `POST /api/ideas/{id}/interpret` (default: `true`). Set to `false` to temporarily fall back to direct `interpret_idea` behavior during phased rollout. |
| `ENFORCE_INTERPRET_CONFIRMATION` | Global server enforcement for idea promotion when `pipelineResult.uncertainty.requiresConfirmation=true` and request has not acknowledged ambiguity (default: `false`). |
| `ENFORCE_INTERPRET_CONFIRMATION_WEB` | Platform-specific enforcement for web clients (`X-Roam-Client: web`) during staged rollout (default: `false`). |
| `ENFORCE_INTERPRET_CONFIRMATION_IOS` | Platform-specific enforcement for iOS clients (`X-Roam-Client: ios`) during staged rollout (default: `false`). |
| `DEV_AUTH_BYPASS` | Local-only switch for backend auth bypass (default: `false`). Only considered when `ENVIRONMENT=dev`. |
| `DEV_AUTH_BYPASS_SECRET` | Shared secret required in `X-Dev-Auth-Bypass` header when backend bypass is enabled. |
| `DEV_AUTH_BYPASS_UID` | Synthetic Firebase UID used when bypass succeeds (default: `dev-auth-user`). |
| `DEV_AUTH_BYPASS_EMAIL` | Synthetic email used when bypass succeeds (default: `dev-auth@local.test`). |
| `GCS_SERVICE_ACCOUNT_JSON` | **Secret.** JSON key for a GCP service account that can **read and write** objects in the reel bucket. Used to upload thumbnails after ingest and to mint **signed GET URLs** for clients. **Both** this and `GCS_REEL_BUCKET_NAME` must be set for server-side thumbnails; omitting either disables GCS in the API. Never log this value. |
| `GCS_REEL_BUCKET_NAME`     | **GCS bucket name** (e.g. `roam-reel-thumbnails-prod`) for reel **thumbnail** JPEGs. The DB stores only the object **key** on `saved_reels.thumbnailObjectPath` (pattern `reels/{userId}/{jobId}/thumb.jpg`); the bucket holds the bytes. If GCS is not configured, ingestion still runs but thumbnails may be missing in the UI.          |

## Notes

- In **dev**, CORS is set to `http://localhost:3000` only; `CORS_ORIGINS` / `FRONTEND_ORIGIN` are not used.
- In **prod**, set `CORS_ORIGINS` (or `FRONTEND_ORIGIN`) so the web app and iOS app (if calling from a web view) can reach the API.
- Configure usage/rate limits in the [Google AI Studio](https://aistudio.google.com/) and [Google Cloud](https://console.cloud.google.com/) dashboards to avoid unexpected bills.
- **GCS:** Create a bucket in the same GCP project you use for Cloud Run (or ensure the service account has cross-project access), grant the SA **Storage Object Admin** (or narrower read/write on that bucket), and store the key JSON in Secret Manager / Cloud Run secrets as `GCS_SERVICE_ACCOUNT_JSON`.

## Frontend local bypass vars

When testing web locally without Firebase login, set these in `frontend/.env.local`:

- `VITE_DEV_AUTH_BYPASS=true`
- `VITE_DEV_AUTH_BYPASS_SECRET=<same value as DEV_AUTH_BYPASS_SECRET>`

## Local quickstart (dev auth bypass)

Backend:

```sh
ENVIRONMENT=dev \
DATABASE_URL=sqlite:///./dev.db \
DEV_AUTH_BYPASS=true \
DEV_AUTH_BYPASS_SECRET=local-dev-secret \
DEV_AUTH_BYPASS_UID=dev-auth-user \
uvicorn app.main:app --reload --port 8000
```

Frontend (`frontend/.env.local`):

```sh
VITE_ENVIRONMENT=dev
VITE_API_BASE_URL=http://127.0.0.1:8000
VITE_DEV_AUTH_BYPASS=true
VITE_DEV_AUTH_BYPASS_SECRET=local-dev-secret
```

Example API call with bypass header:

```sh
curl -H "X-Dev-Auth-Bypass: local-dev-secret" http://127.0.0.1:8000/api/me
```
