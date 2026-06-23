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
| T4 | Refresh token | **S** — theft / replay | Opaque, hashed at rest, rotated each use, family revoke on reuse | Implemented (B2) |
| T5 | `/me`, bookings | **T/E** — act on another user's data | Principal from token `sub`; `/me` is self-scoped (no client id trusted). Bookings extend this in a later slice. | Implemented (B2, /me) |
| T6 | Any input | **T** — injection / over-trust | Boundary validation; parameterized queries (B3); server-authoritative prices/ids | Ongoing |
| T7 | Logs / errors | **I** — leak tokens / PII / internals | Redaction; generic 5xx; no stack traces in responses | Enforced |
| T8 | Secrets | **I** — committed credentials | gitleaks in CI; env-only config; `.env` gitignored | Enforced |
| T9 | Dependencies | **various** — known CVEs | OSV scan in CI; Dependabot updates | Enforced |
| T10 | Provider read (B1) | **I** — exposure of non-public data | Only public provider fields served; no secrets in the model | Enforced |

---

*Changes to these rules must land in this file in the same PR (keep the
guardrails honest). Pointer lives in the `myweli-dev-guardrails` skill.*
