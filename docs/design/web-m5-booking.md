# Web M5 — booking funnel `/(slug)/reserver` (OTP + no-custody deposit)

| | |
|---|---|
| **Requirement** | FR-WEB-PP-003 (web booking) + FR-WEB-PP-004 (no-custody web deposit). |
| **Milestone** | M5 ([public-web.md](public-web.md) §11). The conversion step. |
| **Surface** | `web/` — `app/[slug]/reserver` + BFF route handlers (`app/api/*`). |
| **Skill** | `myweli-web-guardrails`. |
| **Status** | **Built** — `/(slug)/reserver` stepper + BFF (`/api/*`) + httpOnly-cookie session; 25 unit + 7 e2e (full funnel). Silent refresh + web deposit-screenshot deferred (M6/follow-up). |
| **First** | authed + write web flow → brings the **web session** online. |

## 1. Goal
Let a visitor book **on the web, no app install** (FR-WEB-PP-003), converting the
SEO traffic on-page. Replaces the provider page's interim « Réserver → app ».

## 2. Web session — decision (BFF + httpOnly cookies)
Use **Next route handlers as a BFF** (`web/app/api/*`):
- Browser → **Next** (same-origin, **no CORS**, no tokens in JS).
- Next handler → **dart_frog API** (server-side, bearer); refresh token kept in an
  **`httpOnly`, `Secure`, `SameSite=Lax` cookie** on the Next origin; access token
  held server-side per request (refreshed on 401 via `/auth/refresh`).
- **No backend change** — reuses `/auth/otp/*`, `/auth/refresh`, `/appointments`.
  (The M1 CORS stays for any future direct calls; this flow doesn't need it.)
- Handlers: `POST /api/auth/request-otp` · `POST /api/auth/verify` (sets the
  cookie) · `POST /api/bookings` (authed, creates the appointment) · optional
  `POST /api/auth/logout` (clears it). CSRF: `SameSite=Lax` + same-origin only.

## 3. Funnel — decision (single page, stepper)
`app/[slug]/reserver` (client component; provider fetched server-side, 404 if the
slug isn't a provider). One page, progressive **stepper**:
1. **Service(s)** — multi-select from the provider's services (price range +
   duration); running total + total duration.
2. **Staff** (optional) — "Sans préférence" or a specific artist.
3. **Créneau** — date picker → `GET /availability?providerId&date&serviceIds&durationMinutes`
   (public) → slot grid.
4. **Confirmation + OTP** — recap (services, staff, date/time, total, deposit if
   any). Phone → `request-otp` → 6-digit code → `verify` (sets session) →
   `POST /api/bookings` → booking **pending**. (Auth at confirm mirrors the app;
   the booking then also appears in the user's app — FR-APPT-008.)
5. **Acompte (if the salon requires one)** — **no-custody**: show the salon's Wave
   deep link / copyable Mobile Money number + the **exact amount** (server-derived
   deposit). Booking stays **pending** until the salon confirms. The proof
   **screenshot is attached in the app** (web V1 doesn't do the signed upload) —
   a clear "continuez dans l'app" card + install push.

## 4. States (every step)
loading (slots) · empty (no slots that day → suggest another date) · error (OTP
invalid/expired/rate-limited; network; slot taken on submit → 409 "créneau
indisponible, choisissez-en un autre") · success (booking confirmed/pending) ·
auth (the OTP step itself). Server is authoritative on **price, total, deposit,
slot** — the client never sets them; recompute/verify server-side.

## 5. Security
- httpOnly-cookie session (no token in JS/localStorage); same-origin BFF (no CORS
  surface for auth/booking); validate inputs; OTP rate-limit/lockout already
  enforced by the API; deposit amount is **server-derived** (no client price).
- Threat model: the BFF never exposes the refresh token to the page; booking is
  created under the verified principal only.

## 6. Performance
The funnel is a client island on an otherwise-static route; code-split, minimal
deps. Slot fetch is on-demand per date. CWV budget still applies to the route shell.

## 7. Components (`web/components/booking/`)
`BookingStepper`, `ServiceStep`, `StaffStep`, `SlotStep`, `ConfirmStep` (recap +
OTP), `DepositStep` (no-custody) + `lib/api/booking.ts` (BFF client wrappers) +
the `app/api/*` route handlers + `lib/session.ts` (cookie helpers).

## 8. Tests
- **Unit (Vitest):** the BFF handlers (request-otp/verify set cookie; bookings
  attaches bearer + maps errors), the stepper reducer (service→staff→slot→confirm
  transitions, total/duration), deposit display (amount, Wave link).
- **e2e (Playwright):** full happy path against the stub (select service → slot →
  OTP `devCode` → booking pending → deposit instructions); slot-taken → 409
  message; invalid OTP → error. Extend the stub with `/availability`,
  `/auth/otp/*`, `POST /appointments`.
- Lighthouse budget unaffected (funnel is behind interaction).

## 9. Rollout
Additive; no backend change. Provider page « Réserver » → `/<slug>/reserver`
(replaces the app-link interim). Deployed with the rest; the app store/deep-link
+ Wave link config filled at the accounts phase.

## 10. Open questions (proposed defaults)
- **OQ-M5-1 Session** = Next BFF + httpOnly cookie → default (vs browser→API+CORS).
- **OQ-M5-2 Funnel** = single page + stepper → default (vs multi-route wizard).
- **OQ-M5-3 Deposit** = no-custody instructions + booking pending; **screenshot
  proof in the app** (web upload deferred) → default.
- **OQ-M5-4 Auth** = OTP required at confirm (no guest booking) → default.
