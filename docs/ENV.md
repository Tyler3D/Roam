# Backend environment variables

Used by the Roam API (FastAPI) when running locally or on Cloud Run.

## Required

| Variable | Description |
|----------|-------------|
| `ENVIRONMENT` | `dev` or `prod`. |
| `DATABASE_URL` | PostgreSQL connection URL (e.g. `postgresql://user:pass@host:5432/dbname`). |
| `GEMINI_API_KEY` | Google Gemini API key for idea interpretation and reel vision processing. |
| `FIREBASE_PROJECT_ID` | Firebase project ID for token verification. |
| `FIREBASE_PRIVATE_KEY_ID` | Firebase service account private key ID. |
| `FIREBASE_PRIVATE_KEY` | Firebase service account private key (escape newlines as `\n`). |
| `FIREBASE_CLIENT_EMAIL` | Firebase service account client email. |

## Optional

| Variable | Description |
|----------|-------------|
| `GEMINI_MODEL` | Gemini model name (default: `gemini-2.5-flash`). Used for scribble interpret and reel vision. |
| `CORS_ORIGINS` | Comma-separated allowed origins in prod (e.g. `https://app.example.com,https://www.example.com`). If unset, `FRONTEND_ORIGIN` is used. |
| `FRONTEND_ORIGIN` | Single allowed origin in prod. Ignored if `CORS_ORIGINS` is set. |
| `TRUSTED_AUTH_PROVIDERS` | Comma-separated Firebase sign-in providers that skip email verification (default: `google.com,password`). |
| `GOOGLE_MAPS_API_KEY` | Google Maps Places API key for resolving place addresses. If unset, ingestion still runs but places are not geocoded. |

## Notes

- In **dev**, CORS is set to `http://localhost:3000` only; `CORS_ORIGINS` / `FRONTEND_ORIGIN` are not used.
- In **prod**, set `CORS_ORIGINS` (or `FRONTEND_ORIGIN`) so the web app and iOS app (if calling from a web view) can reach the API.
- Configure usage/rate limits in the [Google AI Studio](https://aistudio.google.com/) and [Google Cloud](https://console.cloud.google.com/) dashboards to avoid unexpected bills.
