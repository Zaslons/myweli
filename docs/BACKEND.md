# Myweli backend — engineering guide

The server-side companion to the `myweli-dev-guardrails` skill and ROADMAP
Parts 5–7. Where the skill governs the Flutter app, **this document governs
`backend/`** (the `dart_frog` REST API). It is the source of truth for backend
architecture, conventions, security, performance, testing, and the Definition
of Done. Read it before adding an endpoint; update it when a decision changes a
rule (same discipline as the app).

> **Scope today:** V1 facilitation backend. No custody of funds (PRD OQ-1).
> Real Mobile Money, WhatsApp/SMS, and FCM are deferred — see PRD §8.

---

## 1. Architecture & layering

One direction of dependency, mirroring the app's `interface → impl` discipline
so swapping in Postgres later stays localized:

```
routes/         thin HTTP handlers — parse, authorize, delegate, shape response
  └─ services/  business logic (no HTTP, no SQL) — the testable core
       └─ repositories/  data access behind an interface
            (in-memory now → Postgres later; the swap touches only this layer)
                 └─ models / DTOs  (mirror docs/api/openapi.yaml field-for-field)
middleware/     cross-cutting: auth principal, request-id, error→envelope, logging
```

Rules:
- **A route never touches storage directly** and never holds business rules — it
  validates input, calls a service, maps the result to an HTTP response.
- **A service never imports `dart_frog`** — it takes/returns plain Dart, so it is
  unit-testable without a request. Business invariants live here.
- **A repository is an interface** with an in-memory impl now; the Postgres impl
  (B3) satisfies the same interface. No SQL leaks above this layer.
- **DTO shapes are the contract.** Request/response JSON matches
  [`docs/api/openapi.yaml`](api/openapi.yaml). The contract changes *with* the
  code in the same PR, never after.

## 2. Conventions

- **Error envelope** — every non-2xx returns
  `{ "error": "<machine_code>", "message": "<human, optional>" }` with the right
  status. `error` is a stable snake_case code the app can branch on
  (`otp_expired`, `not_found`, `unauthorized`, …). The app's `ApiResponse.code`
  already consumes this.
- **Status codes** — 200/201/202/204 success; 400 validation; 401 unauthenticated;
  403 authenticated-but-forbidden; 404 missing; 409 conflict; 422 semantic;
  429 rate-limited; 5xx only for genuine server faults.
- **Never leak internals** — no stack traces, SQL, or framework errors in a
  response body. Catch at the edge, log with a request-id, return a generic 500.
- **Method gating** — handlers reject unsupported verbs with 405.
- **Pagination** — list endpoints return `{ items, page, pageSize, total }`;
  `pageSize` is clamped server-side (default 20, max 50).
- **Time** — UTC ISO-8601 everywhere.

## 3. Security model (server-side companion to ROADMAP Part 5)

Security is gated from the first endpoint, not deferred. Reference: OWASP ASVS.

### 3.1 AuthN — tokens & sessions  *(decision: JWT access + rotating refresh)*
- **Access token**: short-lived signed **JWT** (HS256, TTL ~15 min). Claims:
  `sub` (user/provider id), `role` (`user` | `provider`), `iat`, `exp`, `jti`.
  Verified statelessly by middleware; no DB hit on the hot path.
- **Refresh token**: long-lived **opaque** random (≥256-bit), returned once,
  **stored only as a hash** (SHA-256) server-side. **Rotated on every use**;
  the old one is invalidated. **Reuse detection**: presenting an already-rotated
  refresh token revokes the whole token family (stolen-token containment).
- **Session lifetime**: "until logout" UX via silent refresh (short access +
  long refresh). Logout revokes the refresh family and the app clears
  `flutter_secure_storage`.
- **Signing key** (`JWT_SECRET`) comes from env — never in code or git.

### 3.2 OTP
- Codes are **hashed at rest** with a short TTL; **never logged**.
- **Server-side rate-limit + lockout**, mirroring the app: a wrong-attempt
  budget per code and a resend budget per phone (429 + `otp_*` codes when
  exceeded). The client UI hints are convenience; the server is the authority.
- **Dev codes** are returned inline (`devCode`) **only when `ENV != prod`**.
  Production sends via the SMS/WhatsApp provider (deferred) and returns nothing.

### 3.3 AuthZ
- **Deny by default.** Protected routes require a valid access token; middleware
  resolves the principal and rejects with 401 if absent/invalid.
- **Ownership checks on every resource** — a user may only read/mutate their own
  data (`/me`, their bookings); a provider only their salon. Mismatch → 403.
  Never trust an id from the client to imply permission.

### 3.4 Input validation & server authority
- Validate/parse **every** input at the boundary: phone (E.164, +225 default),
  OTP format, body schema, enum membership, numeric ranges. Reject with 400 +
  code. Unknown fields ignored, not trusted.
- **The server is the authority** on prices, totals, ids, status, and
  permissions. The client proposes; the server computes and verifies. (E.g.,
  deposit amount is derived server-side from the service price × policy, not
  taken from the request.)

### 3.5 Secrets & config
- **No secrets in code or git.** Config via env: `JWT_SECRET`, `DATABASE_URL`,
  provider keys (later). Dev uses a gitignored `.env` (see `backend/.env.example`).
- **CI secret scanning** (gitleaks) fails the build on any committed credential.

### 3.6 Transport & logging
- **TLS** in every non-local environment.
- **Structured logs** with a request-id; **never log** OTPs, tokens, refresh
  hashes, `Authorization` headers, or PII. Redact by default.
- Security headers on responses where applicable; CORS locked to known origins
  (the web app) in prod.

### 3.7 Idempotency (reserved)
- Mutating money/booking endpoints (later slices) require an **idempotency key**
  and are safe to retry. Documented now; enforced when those slices land.

### 3.8 Threat model
A living STRIDE table (§7) is updated **in the same PR** that adds a new endpoint
or trust boundary. No new surface ships without a threat-model line.

## 4. Performance budgets (companion to ROADMAP Part 6)

Same low-end-Android, bad-network reality drives the API:
- **Read p95 < 200 ms** server-side (excluding network) for cached/simple reads;
  **< 500 ms** for slot computation.
- **Pagination everywhere**; never return an unbounded list.
- **No N+1**: batch/join in the repository; the slot engine precomputes.
- **Connection pooling** for Postgres; **Redis** for hot reads (provider lists,
  availability) and rate-limit counters (B3+).
- Keep payloads lean; compress; image bytes come from object storage/CDN, never
  proxied through the API.

## 5. Testing strategy (companion to ROADMAP Part 4)

Every PR is tested; treat an unchecked box as "not done":
- **Unit** — services & repositories (pure logic: filtering, OTP budget, token
  rotation, ownership).
- **Handler tests** — per route: success, 4xx branches, 405.
- **Contract tests** — responses conform to the OpenAPI schema for that path.
- **Security / negative tests (required gate)** — expired/invalid/replayed
  tokens, missing auth, rate-limit/lockout, cross-tenant access (A's token on
  B's resource → 403). These are not optional.
- **Load tests** — slot engine and (later) payment callbacks, before they ship.
- Coverage must not decrease.

## 6. Definition of Done — backend PR gates

- [ ] **Design spec written first** in [`docs/design/`](design/README.md) (per [`docs/design/TEMPLATE.md`](design/TEMPLATE.md)), aligned, and cross-linked from the routes/services/contract it governs.
- [ ] `dart format` clean · `dart analyze --fatal-infos --fatal-warnings` = **0**.
- [ ] Tests green, including the **security/negative** tests for any auth-touching change.
- [ ] **Contract updated** in the same PR (`docs/api/openapi.yaml`); responses match it.
- [ ] **No secrets** added; gitleaks clean; new config via env + `.env.example`.
- [ ] **Dependency scan** clean (OSV); no known-vulnerable packages added.
- [ ] **AuthZ**: deny-by-default + ownership checks on any new resource.
- [ ] **Threat model (§7) updated** if the PR adds an endpoint or trust boundary.
- [ ] Errors use the standard envelope; no internal leakage; correct status codes.
- [ ] Performance budget respected (paginated, no N+1).
- [ ] **ROADMAP refreshed** (slice status).
- [ ] Branch + PR (never push `main`); CI green before requesting merge.

## 7. Threat model (living — STRIDE)

Seeded for the surfaces shipped/known. Extend per slice.

| # | Surface | Threat (STRIDE) | Mitigation | Status |
|---|---------|-----------------|------------|--------|
| T1 | OTP request | **S/D** — SMS-bomb / enumeration | Per-phone resend budget + lockout (429); generic responses; provider-side cost caps (later) | Implemented (B2) |
| T2 | OTP verify | **S** — brute-force the code | Wrong-attempt budget + lockout; short TTL; hashed at rest | Implemented (B2) |
| T3 | Access token | **S/E** — forgery / privilege escalation | Signed JWT (HS256), `exp` ~15 min, `role` claim, deny-by-default middleware | Implemented (B2) |
| T4 | Refresh token | **S** — theft / replay | Opaque, hashed at rest, rotated each use, family revoke on reuse — same flow for consumer (`refresh_tokens`) and provider (`provider_refresh_tokens`, FK to the account) | Implemented (B2 consumer; B-prov provider) |
| T5 | `/me`, `/me/favorites`, bookings | **T/E** — act on another user's data | Principal from token `sub`; `/me` + `/me/favorites` (list/add/remove) self-scoped — no user id is accepted from the client, and favorites is consumer-only (provider token → 403); consumer appointments scoped/owned (403). **Provider reads/transitions** require `role=provider` **and** the account's linked `providerId`: `GET /appointments` returns only that salon's bookings (unlinked → 403), a transition's appointment `providerId` must match (cross-salon → 403), and the catalogue/availability/**dashboard**/**earnings**/**manual-booking** reads+writes (`/providers/{id}/…`) check `account.providerId == {id}` (→ 403). | Implemented (B2 /me; consumer + pro appointments; B-cat; B-dash; B-earn; B-manual) |
| T6 | Any input | **T** — injection / over-trust | Boundary validation; **parameterized queries everywhere** (B3c Postgres repos); server-authoritative prices/ids | Enforced |
| T7 | Logs / errors | **I** — leak tokens / PII / internals | Redaction; generic 5xx; no stack traces in responses | Enforced |
| T8 | Secrets | **I** — committed credentials | gitleaks in CI; env-only config; `.env` gitignored | Enforced |
| T9 | Dependencies | **various** — known CVEs | OSV scan in CI; Dependabot updates | Enforced |
| T10 | Provider read (B1) | **I** — exposure of non-public data | Only public provider fields served; no secrets in the model | Enforced |
| T11 | Booking / reschedule (consumer **and pro**) | **T** — overbooking / book a closed/past/taken slot / move another party's booking | App-level slot-engine validation → `slot_unavailable` (409), **plus** a Postgres **partial unique index** on `(provider_id, appointment_date)` for non-cancelled statuses → atomic exact-start collision rejection under concurrency. Reschedule is **role-aware** and ownership-scoped: a `user` may only move their own booking (by `userId`), a `provider` only its own salon's (by linked `providerId`) — cross-party → 403; both go through the same slot guard. A **`btree_gist` EXCLUDE constraint** then rejects any **duration overlap** per provider — `tstzrange(appointment_date, appointment_date + duration_minutes) WITH &&` for `pending`/`confirmed` — so non-exact overlaps can't slip through under concurrency either (`create`/reschedule `update` map the `23P01` violation to `slot_unavailable`). Buffer stays an app-level slot-engine concern. | Implemented (app + DB exact-start **+ duration-overlap exclusion**; consumer + pro reschedule) |
| T15 | KYC (`/uploads/sign?purpose=kyc`, `/me/kyc`) | **I/T/E** — leak ID documents / submit another salon's KYC / tamper with verification | Provider-only + **self-scoped** (the object key prefix `kyc/{accountId}` and the account are the token's `sub`); submit re-checks each key is under the caller's own prefix. ID docs upload to a **separate private bucket** (`R2_KYC_BUCKET`, no public domain), uuid-named keys, no public URL ever, bytes never through the API. `verificationStatus`/`rejectionReason` are **server-owned** (only the future admin flips them). In-app viewing (signed-GET, owner/admin-only) + approve/reject are the **admin slice** (now implemented — see **T17**: admins view docs via signed-GET and approve/reject with reason, audited). | Implemented (B-kyc provider side **+ admin verify/viewing via T17**) |
| T17 | Admin / ops (`/admin/*`) | **E/I/S** — privilege escalation to the global admin surface / staff reading or tampering with everyone's data / no accountability | **Deny-by-default trust boundary**: `/admin/*` requires `role=admin` (the one surface that intentionally bypasses tenant ownership), enforced in `routes/admin/_middleware.dart` before any handler; `/admin/auth` is the only unauthenticated path. Admin accounts are **seeded only** (no self-signup), **email + password hashed with bcrypt**, login **rate-limited + lockout**, refresh **rotated + family-revoke** (like consumer/provider). **Every mutation is written to an append-only `audit_log`** (actor, action, target, reason) — approvals, rejections (reason required), and (later) suspensions/moderation. KYC ID docs are viewable only via short-TTL **signed-GET** (admin-authorized; bytes never through the API). **Slice 2/A3 (provider management):** admin can **suspend** a provider (server-owned `providers.status`) → excluded from discovery (`query` filters) **and** new bookings rejected (`BookingService` → `provider_suspended`), login unaffected; **restore** reverses it; **feature** toggles homepage placement — all audited; read-only support views (provider + recent bookings), **no act-as token** (deferred). **A3b (consumer):** admin **ban** a user (`users.status`) → **login blocked** (`verifyOtp` → `account_suspended`, 403; tokens are short-lived so existing sessions die fast), **unban** reverses it; read-only user support views (user + recent bookings); audited. **A4 (disputes):** admin opens a **dispute record** on a booking (reason + evidence: the appointment + a signed deposit-screenshot URL — admins are authorized on `DepositService.screenshotUrl`) and **resolves** it with an outcome — audited; **no money moves** (no-custody), the consequence is applied via suspend/ban. | Implemented (Slice 1 + Slice 2 complete) |
| T16 | Deposit screenshot (`/uploads/sign?purpose=deposit`, `/appointments/{id}/deposit`, `/appointments/{id}/deposit-screenshot`) | **I/T** — leak a payment proof (amounts/phone/refs) / attach proof to another user's booking / move money through Myweli | **No custody** — the server records the screenshot key + status; it never holds or settles funds (PRD §6.1). Upload is **consumer-only, self-scoped** (key prefix `deposit/{userId}`, the token's `sub`); submit re-checks the key is under the caller's prefix, on the caller's **own** `pending` booking (cross-user/non-owner → 403, wrong key → 400). Screenshots land in a **dedicated private bucket** (`R2_DEPOSIT_BUCKET`, separate from KYC for independent retention / credential scope / blast-radius; no public domain), uuid-named, **no public URL ever**, bytes never through the API. Viewing is a **short-TTL signed-GET** restricted to the booking's **consumer, its salon, or an admin** (dispute evidence, T17). `depositAmount` stays **server-computed** from the policy. | Implemented (B-deposit) |
| T14 | Reviews (`/appointments/{id}/review`, `/providers/{id}/reviews`) | **S/T** — fake/forged review, rate another salon up/down, tamper with the rating | Submit is consumer-only and **of the caller's own `completed` appointment** (→ 403); the server derives author, `verified`, attribution (artist/service), and recomputes the provider+artist **rating** from reviews — none are client-settable. **One review per appointment** (upsert) limits ballot-stuffing. Content validated/bounded; photo origins allowlisted like the gallery. `GET` is public read-only. **Moderation (T17/A2):** consumers `report` a review (idempotent per reporter; stays visible until acted — no weaponized auto-hide); an admin **hides** (excluded from feed **and** rating recompute), **dismisses**, or **restores** — all audited. | Implemented (B-reviews + admin moderation) |
| T13 | Image upload (`/uploads/sign`) | **T/E/D** — write to another salon's storage / upload arbitrary or oversized content / proxy bytes through the API | Provider-only; the object **key is built server-side from the token's `providerId`** (no client-chosen path → no cross-salon write / traversal). The presigned **POST policy** pins the key, **content-type allowlist** (jpeg/png/webp), and a **`content-length-range`** size cap — storage rejects anything else; short TTL (~5 min). Bytes go client → storage directly (R2), never through the API. R2 secrets via env (never logged). Content/NSFW + virus scanning deferred (later hardening). | Implemented (B-upload) |
| T18 | OTP delivery over SMS (`/auth/otp/request` → `MessagingService.sendOtp`) | **I/D** — intercept the code / log or leak it / spam SMS | The code is hashed at rest (unchanged); the plaintext is carried in-memory only to the sender and **never logged or persisted** (OTP goes via `sendOtp`, not the outbox). SMS interception is an accepted residual risk, bounded by the existing short TTL + attempt-lockout + resend cap. Send is **best-effort** (failure never blocks the flow). | Implemented (PR A — messaging foundation) |
| T19 | Messaging status webhook (`/webhooks/messaging/status`) | **S/T** — spoof delivery status / forge outbox state | Guarded by a shared `?secret=` (`MESSAGING_WEBHOOK_SECRET`) — **deny-by-default** when configured; only `MessageSid`+`MessageStatus` are read; unknown ids are no-ops (idempotent, always 200); no PII echoed. Real Twilio request-signature validation is a tracked follow-up. | Implemented (PR A) |
| T20 | Promotional messaging (`MessageTemplate.rebookReminder`) | **Compliance** — sending marketing without consent (ARTCI / WhatsApp policy) | Promotional templates are gated on `messaging_opt_out`; **transactional always sends**. Opt-out is persisted (`MessagingPrefsRepository`). | Implemented (PR A) |
| T21 | Reminder cron (`/internal/cron/reminders`) | **E/D** — an attacker triggers reminder blasts / message spam | **Deny-by-default**: `CRON_SECRET` required (`X-Cron-Secret`/`?secret=`) — **404 when unset** (no surface), 403 on mismatch. Each tick is **idempotent** via `appointment_reminders` (PK `(appointment_id, kind)` + `ON CONFLICT DO NOTHING`), so repeated calls never re-send. Booking-event notifications are **best-effort** and never block a transition. | Implemented (PR B) |
| T22 | Push / device tokens (`/me/devices`, FCM) | **I/E** — register a token to another user / harvest tokens / leak in pushes | Registration is **self-scoped** to the authed principal (`user_id` = token `sub`); unregister only removes the caller's own token; re-registering a token reassigns ownership (device hand-off). FCM **service-account** creds via env only (never the repo; gitleaks); fail-fast in prod. Pushes carry only the booking summary already sent via SMS/WhatsApp; provider-reported **invalid tokens are pruned** (no indefinite fan-out). Send is **best-effort**. | Implemented (FCM foundation) |
| T23 | In-app notifications (`/me/notifications*`) | **I** — read or mark another user's notifications | Every list/mark is **filtered by `user_id = principal.sub`**; `list` returns only the caller's, `mark-read` of a foreign/absent id → **404** (never leaks existence), `read-all` only touches the caller's. Authed only; the body carries only the booking summary already sent over the other channels. Written best-effort by `BookingNotifier` on lifecycle events. | Implemented (notification center) |
| T24 | Notification preferences (`/me/notification-preferences`) | **T/I** — toggle another user's prefs / disable service messages / enumerate | **Self-scoped**: read/write keyed by `principal.userId` with **no path id** (nothing to enumerate or cross-access). The server honours only the three known boolean fields (non-bool → **400**); transactional service categories are not exposed, so a client cannot suppress confirmations. Enforcement is server-side in `BookingNotifier` (reminders/marketing gate messaging + push by category; `push` gates the channel). No new PII. | Implemented (FR-NOTIF-004 PR1) |
| T12 | Catalogue mgmt (`/providers/{id}/services`, `/availability`, `/gallery`, `/before-after`, `/deposit-policy`, `/artists`) | **T/E** — edit another salon's catalogue / hours / photos / deposit terms / staff | `role=provider` **and** ownership: the account's linked `providerId` must equal `{id}` (cross-salon / unlinked → 403). Boundary validation (name/price/duration/time-windows → 400; gallery = list of non-empty URL strings, ≤20, ≤2048 chars; **deposit** = % in 0..1 (>0 when required), window 0..720h, operator enum, E.164 number, MoMo handle required when a deposit is required; **artist** name non-empty); server sets `id`/`providerId` (and **artist `rating`/`reviewCount` are server-owned from reviews**); a disabled service (`active=false`) is rejected by booking. The **deposit policy is server-authoritative** — booking derives each deposit from the stored policy, never from the client. **Gallery** stores only URLs (no bytes through the API); when public delivery is configured the gallery `PUT` **allowlists our own origin** (+ `asset:` seed) — rejecting foreign URLs (anti-SSRF/hotlink). | Implemented (B-cat; B-gallery URL list; B-upload origin-allowlist) |

---

*Changes to these rules must land in this file in the same PR (keep the
guardrails honest). Pointer lives in the `myweli-dev-guardrails` skill.*
