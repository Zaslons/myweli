# Web M6 — consumer account (login · my bookings · session)

| | |
|---|---|
| **Requirement** | FR-WEB-MP-002 (account login + my bookings on web). |
| **Milestone** | M6 ([public-web.md](public-web.md) §11). Completes the consumer web loop (book → manage). |
| **Surface** | Backend (tiny: `GET /me`) + `web/` (account pages + BFF). |
| **Skills** | `myweli-web-guardrails` (+ `myweli-backend-guardrails` for `GET /me`). |
| **Status** | **Built** — `GET /me` (backend) + `/connexion` · `/mon-compte` · `/mon-compte/[id]` + BFF `callApi` **silent refresh** + logout; 32 web unit + 9 e2e, backend +4 (`/me` GET). Reschedule/profile-edit/reviews/favorites/delete deferred to the app. |

## 1. Goal
Let a signed-in consumer **manage on the web** what they booked: log in (phone/
OTP), see their appointments (incl. salon-entered ones via FR-APPT-008), view a
booking and **cancel** it, see their profile, and log out — with a **long-lived
session** (BFF silent refresh, the deferred M5 item).

## 2. Backend (small) — `GET /me`
`/me` today has PATCH/DELETE but **no GET**. Add **`GET /me`** → the signed-in
user's profile (`{id, name, phoneNumber, email, avatarUrl, createdAt}`),
self-scoped (principal only). Powers the web session check + profile. OpenAPI +
a handler test + threat-model note (self-scoped read, no new exposure). *(backend
guardrails.)*

## 3. Web session — silent refresh (finishes M5's BFF)
A shared **`authedApiFetch`** in the BFF: attach the access cookie; on **401**,
use the refresh cookie → `POST /auth/refresh` → rotate → **update both cookies** →
retry once; if refresh fails → 401 (the page redirects to `/connexion`). Used by
all authed BFF handlers (`/api/me`, `/api/appointments*`, and retrofitted into
`/api/bookings`).

## 4. Routes & UX
- **`/connexion`** — phone → OTP (reuses the M5 BFF); on success redirect to
  `returnTo` (default `/mon-compte`). Already-signed-in → redirect to `/mon-compte`.
- **`/mon-compte`** — authed (server reads session via `/api/me`; no session →
  redirect `/connexion?returnTo=/mon-compte`). Shows: profile summary (name,
  phone) + **logout**; **My bookings** with **Upcoming / Past / Cancelled** tabs
  (`GET /appointments`), each an `AppointmentCard` (provider, date/time, status,
  total; a "Réservé par votre salon" hint when salon-entered) → links to detail.
- **`/mon-compte/[id]`** — appointment detail: status, services, provider,
  date/time, deposit/balance, and **Annuler** (policy-bound — shows the deposit
  consequence before confirming; `POST /appointments/{id}/cancel`).
- **BFF:** `GET /api/me`, `GET /api/appointments`, `GET /api/appointments/[id]`,
  `POST /api/appointments/[id]/cancel`, `POST /api/auth/logout` (clears cookies).

## 5. States
loading · empty (no bookings → "Aucun rendez-vous" + a Découvrir CTA) · error
(+retry) · success · **auth-gated** (no session → redirect to `/connexion`). Cancel
shows the policy/deposit consequence; 409/expired → friendly message.

## 6. Security
httpOnly-cookie session (silent refresh; tokens never in JS); every account read/
mutation is **self-scoped** server-side (the principal) — a user only ever sees/
acts on their own data (cross-user → API 403/404). `/mon-compte*` is **`noindex`**
(authed). Logout clears cookies. Same-origin BFF (no CORS surface).

## 7. Scope (decision) — V1 vs deferred
- **In M6:** login, my bookings (list + tabs + detail), **cancel**, profile
  **view**, logout, silent refresh, `GET /me`.
- **Deferred (app, or M6.1):** **reschedule** (re-pick slot — heavier; the app
  does it), **profile edit** (PATCH exists; web form later), **review submission**,
  **favorites**, **account deletion / data export** (sensitive → app-only). Each
  surface nudges "continuer dans l'app".

## 8. Components
`Header` (logo + Mon compte / Se connecter / logout — added to the layout) ·
`OtpLoginForm` (reused by `/connexion`) · `AppointmentCard` (web) · `CancelDialog`
· `lib/api/account.ts` (BFF client wrappers).

## 9. Tests
- **Backend:** `GET /me` 200 (self) · 401 (anon).
- **Unit (web):** the bookings tab filter (upcoming/past/cancelled), the BFF
  silent-refresh helper (401 → refresh → retry; refresh-fail → 401), card render.
- **e2e (Playwright):** log in (OTP) → see a booking → open detail → cancel →
  status updates; **unauthenticated `/mon-compte` → redirect to `/connexion`**.
  Extend the stub with `/me`, `/auth/refresh`, `GET /appointments`,
  `GET/POST /appointments/{id}*`.

## 10. Rollout
Additive; one small backend route (`GET /me`). `/mon-compte*` dynamic + noindex.
Deployed with the rest.

## 11. Open questions (proposed defaults)
- **OQ-M6-1** Add **`GET /me`** (vs cookie-stored user) → default add it.
- **OQ-M6-2** M6 scope = manage/cancel + view (reschedule/edit/delete deferred) → default.
- **OQ-M6-3** Login route `/connexion` with `returnTo` → default.
