## Frontend → Backend Integration Plan

### Current Frontend Snapshot (No Backend)
- All data is in-memory via `useDatePins` and `sampleDatePins`.
- Views: Home, Map, List all read from local state.
- Actions: add pin, update status, delete pin, mark as viewed (all local).
- Map uses Google Maps/Places client-side.
- Supabase client exists but is unused.

Key files:
- `src/hooks/useDatePins.ts` (local CRUD + derived lists)
- `src/pages/Index.tsx` (primary view routing + dialogs)
- `src/components/*` (UI-only)

### Core Backend Needs
Based on current frontend behavior:
- Auth: Firebase sign-in with ID token + refresh handling.
- Users: `/api/users` + `/api/me` + `/api/users/verify`.
- Pins CRUD: list/create/update/delete (scoped by user + shared).
- Mark as viewed.
- Sharing: share with username, collaborator role.
- Filters: search, tag, status, sort (can be server-side or client-side).

### Initial Frontend Changes (Phase 1)
#### 1) Authentication UX
- Add sign-in / sign-up screen.
- Use Firebase Auth SDK for:
  - email/password + Google sign-in.
  - refresh token handling (SDK-managed).
- Store ID token in memory (or local storage if needed).
- Add route protection:
  - If no valid token → redirect to login.
  - If token exists but email not verified and provider not trusted → block.

#### 2) Session Handling
- Use Firebase `onAuthStateChanged` to update app state.
- Use `getIdToken()` for API calls.
- If ID token expires, SDK refreshes automatically.

#### 3) Backend API Integration
- Replace `useDatePins` with a data layer that calls backend:
  - `GET /api/pins` (list)
  - `POST /api/pins` (create)
  - `PATCH /api/pins/{id}` (update status/viewed)
  - `DELETE /api/pins/{id}` (delete)
- Attach `Authorization: Bearer <idToken>` on all API calls.
- Handle 401/403:
  - 401 → force re-auth
  - 403 → prompt verification

#### 4) User Bootstrap
- On first login:
  - Call `POST /api/users` with username + profile info.
- After email verification:
  - Call `POST /api/users/verify`.

### Data/Model Adjustments
- Add `isActive`, `emailVerified` on user profile state.
- Pin data will come from backend; timestamps will be ISO strings → convert to `Date`.
- Tags and ML suggestion fields will become editable fields in UI later.

### Non-Functional Changes
- Remove unused Supabase integration or leave dormant.
- Configure frontend to use port `3000` (Vite).
- Add `VITE_API_BASE_URL` for backend base URL.

### Open Decisions
- Where filtering/sorting happens (client vs server).
- How shared pins are visually differentiated.
- Whether to show "verification required" screen or inline banner.

### Suggested Next Steps (Short Term)
1) Add Firebase Auth + protected routes.
2) Implement `/api/users` + `/api/me` bootstrap in UI.
3) Replace `useDatePins` with API-backed hooks.
4) Add error handling for 401/403 + verification state.

### API Response Shapes (Draft)
#### Auth / Users
- `POST /api/users`
  - Request:
    - `username`, `email?`, `displayName?`, `photoUrl?`
  - Response:
    - `id`, `firebaseUid`, `username`, `email`, `displayName?`, `photoUrl?`,
      `isActive`, `emailVerified`, `createdAt`
- `GET /api/me`
  - Response: same as `/api/users`
- `POST /api/users/verify`
  - Response: same as `/api/users`

#### Pins (planned)
- `GET /api/pins`
  - Response: list of pins
- `POST /api/pins`
  - Request: `title`, `notes?`, `link?`, `locationName?`, `locationLat?`,
    `locationLng?`, `tags?`, `status?`, `sharedWith?`
- `PATCH /api/pins/{id}`
  - Request: partial updates (status, notes, tags, lastViewedAt)
- `DELETE /api/pins/{id}`

### Implementation Checklist (Frontend)
#### Auth & Session
- Add Firebase config + initialize Auth SDK.
- Implement login + signup pages (email/password + Google).
- Add `AuthProvider` context for user state and token management.
- Protect routes; redirect unauthenticated users to `/login`.
- Trigger `/api/users` on first login.
- Trigger `/api/users/verify` after email verification.

#### API Client
- Centralize API base URL (`VITE_API_BASE_URL`).
- Use a single `fetch`/`axios` wrapper that:
  - attaches `Authorization: Bearer <idToken>`
  - handles `401` (re-auth) and `403` (verification prompt)
  - parses date strings into `Date` objects

#### Replace Local State
- Replace `useDatePins` with API-backed hooks:
  - list pins + loading state
  - create/update/delete
  - mark as viewed

#### UX
- Add verification banner or blocking screen until email verified.
- Add shared-pin badge and filtering (later).

