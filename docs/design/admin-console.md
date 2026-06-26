# Admin / ops console — design spec

| | |
|---|---|
| **Status** | Slice 1 **Built** · Slice 2 **Built** (A3 provider · A3b user · A4 disputes) · Slice 3 (analytics) next |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | §11.4 (FR-WEB-AD-001…008), §16 trust & safety, §17 analytics, §18 compliance · V1 basic → V2 full |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ |

## 1. Goal & scope

Stand up Myweli's **internal admin/ops capability** — the back-office the Myweli team uses to verify providers, keep the marketplace safe, and (later) steer supply/demand. Built **backend-first**: the durable, security-critical part (admin **role + trust boundary + immutable audit log** and the admin **API**) is built and tested in this repo now; the **console UI** (stack TBD — Flutter Web vs React) is a later, separate effort.

**Design principles (non-negotiable):**
1. **Least privilege + total auditability** — admin is the one place we *intentionally* cross tenant boundaries, so **every mutation is written to an append-only audit log** (actor, target, before/after, reason).
2. **Queues, not hunts** — work surfaces (KYC pending, reported reviews) are first-class.
3. **Reversible + reasoned** — reject/hide/suspend require a reason and are reversible; reversals are logged too.
4. **No-custody-aware** — Myweli holds no funds (OQ-1); admin **mediates/records** disputes and applies *consequences*, it never moves money.
5. **Safety-first defaults** — unverified providers can't take deposits; no admin self-signup (seeded).

### This slice (Slice 1)
- **A1 — Foundation + KYC queue:** `admin` role + `/admin/*` trust boundary; admin auth (seeded super-admin); **audit log**; **KYC approval queue** (list pending → view ID docs via signed-GET → approve / reject + reason). Closes the deferred admin half of [pro-kyc.md](pro-kyc.md) and unblocks verified providers taking deposits.
- **A2 — Review moderation:** consumer **report a review** (FR-REV-005) → admin **moderation queue** → **hide / restore** (hidden reviews excluded from feed + rating). Closes the moderation half of [consumer-reviews.md](consumer-reviews.md).

### Out of scope (later slices — recorded so the full plan is captured)
- **Slice 2:** provider/user **suspend/ban**, **audited impersonation** (FR-WEB-AD-002); **dispute records** (FR-WEB-AD-003, no money movement); **featured placement** (FR-WEB-AD-005).
- **Slice 2 (now — specced in §12):** provider/user **management** (suspend/ban), **read-only support views**, **featured placement** (FR-WEB-AD-002/005), and admin **dispute records** (FR-WEB-AD-003).
- **Slice 3:** **marketplace-health analytics** read models (FR-WEB-AD-006) — North Star (paid completions/week by commune), supply/demand funnels, guardrails (no-show, dispute rate).
- **Slice 4+:** anti-fraud signals (§16: off-platform leakage, no-show fairness, promo abuse); full product-analytics stack (PostHog/Firebase); **compliance tooling** (ARTCI data export/delete, FR-AUTH-005); admin **sub-roles** (super-admin/moderator/support); the **console UI**.

## 2. UX & flows (API consumer = the future console)
- **Login** → admin JWT. **KYC queue:** list pending providers → open one → see business info + a thumbnail/list of submitted docs (each via a short-lived **signed-GET**) → **Approve** (badge + can take deposits) or **Reject** with a reason the provider sees. **Moderation queue:** list reported (still-visible) reviews with the report reason + the review + booking context → **Hide** (with reason) or **Dismiss the report**; **Restore** a hidden review. **Audit log:** chronological, filterable read. Every action returns the updated entity + writes an audit row.

## 3. API & contract (Slice 1)
All under **`/admin/*`**, `role=admin` only (deny-by-default), every mutation audited.

**Admin auth**
- `POST /admin/auth/login` `{email, password}` → `{accessToken, refreshToken}` (role=admin). Rate-limited + lockout like consumer OTP.
- `POST /admin/auth/refresh` `{refreshToken}` → rotated pair (reuse → revoke family, as elsewhere).

**KYC queue** (FR-WEB-AD-001)
- `GET /admin/kyc?status=pending&page=&pageSize=` → `{ items: [{accountId, businessName, businessType, submittedAt, docCount}], page, pageSize, total }`.
- `GET /admin/kyc/{accountId}` → full account + `docs: [{type, key, viewUrl}]` (each `viewUrl` a signed-GET into the KYC bucket).
- `POST /admin/kyc/{accountId}/approve` → `verificationStatus=verified`. Audited.
- `POST /admin/kyc/{accountId}/reject` `{reason}` (required) → `verificationStatus=rejected`, `rejectionReason`. Audited.

**Review moderation** (FR-WEB-AD-004, FR-REV-005)
- `POST /reviews/{id}/report` `{reason}` — **consumer** auth; creates a report (idempotent per user+review). 
- `GET /admin/reviews/reports?status=open&page=&pageSize=` → reported reviews + report metadata.
- `POST /admin/reviews/{id}/hide` `{reason}` → `moderationStatus=hidden`; recompute provider+artist rating excluding hidden. Audited.
- `POST /admin/reviews/{id}/restore` → `moderationStatus=visible`; recompute. Audited.

**Audit** (FR-WEB-AD-008)
- `GET /admin/audit?page=&pageSize=&actor=&action=` → append-only log (read).

Errors: standard envelope (400/401/403/404/409/422/429). Non-admin token on `/admin/*` → 403. All lists paginated.

## 4. Data model / migrations
- **`admins`** — `id, email (unique), password_hash, status, created_at`. Seeded super-admin from env (`ADMIN_EMAIL` + `ADMIN_PASSWORD` on first boot → hashed). No self-signup.
- **`admin_refresh_tokens`** — mirrors the existing rotating-refresh design (hashed at rest, family-revoke).
- **`audit_log`** (append-only) — `id, actor_admin_id, action, target_type, target_id, reason, metadata jsonb, created_at`. No update/delete path.
- **`review_reports`** — `id, review_id, reporter_user_id, reason, status (open|resolved), created_at, resolved_by, resolved_at`; unique `(review_id, reporter_user_id)`.
- **`reviews`** — add `moderation_status text not null default 'visible'`; the public feed + rating aggregates filter `= 'visible'`.
- **`provider_users`** — `verification_status` / `rejection_reason` already exist (from KYC); admin flips them.

## 5. Architecture & patterns
- **Role/trust boundary:** `Principal.role == 'admin'`; an `/admin` middleware (or per-route guard) rejects non-admins (403) before any handler. This is the *only* surface that bypasses ownership scoping — hence the audit log.
- **Admin auth:** `AdminAuthRepository` (InMemory + Postgres) + reuse `TokenService` (role=admin) + the rotating-refresh pattern. Passwords hashed with a **real KDF** (bcrypt) — *not* sha256 (open question §11).
- **Audit:** `AuditLogRepository` (append + list); a tiny `audit()` helper every admin service calls inside the same logical action. Append-only.
- **Services (no dart_frog/SQL):** `AdminKycService` (queue/detail/approve/reject; uses `ProviderAuthRepository` + `StorageService.presignGet` + audit), `ModerationService` (report/queue/hide/restore + rating recompute; uses `ReviewsRepository` + audit). Routes stay thin.
- **Reuse:** `presignGet` (from the deposit slice) for KYC doc viewing; `ReviewsRepository.updateRatings` for recompute; the pagination envelope.
- **Selection by `DATABASE_URL`** (InMemory vs Postgres), like every repo.

## 6. Security & authz (this IS the trust boundary)
- Deny-by-default on `/admin/*`; `role=admin` required; **no self-signup** (seeded). Admin auth rate-limited + lockout; refresh rotated + family-revoke; secrets via env.
- **Every mutation audited** with actor + reason (append-only) — approvals, rejections, hides, restores.
- KYC **ID docs** are viewable only via short-TTL **signed-GET** issued to an admin (bytes never through the API; no public URL). `verificationStatus`/`rejectionReason` server-owned.
- Consumer report endpoint validated + idempotent (no report-spam); hidden reviews removed from feed **and** excluded from ratings (no moderation-evasion via stale aggregates).
- **Threat model:** new **T17** (admin trust boundary) — global role, deny-by-default, full audit, seeded accounts, KDF-hashed passwords, signed-GET doc access, no impersonation in this slice. Update **T15** (KYC: admin verify + signed-GET viewing now implemented) and **T14** (reviews: moderation now possible).

## 7. Performance
- All lists paginated (clamp pageSize). Queues are indexed reads (`verification_status`, `moderation_status`, report `status`). Rating recompute on hide/restore is the existing single-provider aggregate (no N+1). Signed-GET is pure HMAC.

## 8. Testing plan
- **Auth/trust boundary:** non-admin token → 403 on `/admin/*`; admin login/refresh happy + bad-password + lockout; rotated refresh reuse → revoke.
- **Audit:** every mutation writes exactly one audit row (actor/action/target/reason); log is append-only + readable.
- **KYC:** queue lists only pending; detail returns signed doc URLs; approve → verified; reject requires reason → rejected + reason; non-pending transitions handled.
- **Moderation:** consumer report (idempotent, validated); hide → excluded from public feed + rating recomputed; restore → back + recomputed; admin-only on the moderation mutations.
- DB-gated (Postgres) tests for the new tables/migrations + indexes (CI Postgres job).

## 9. Definition of done (per PR)
- [ ] `dart format` · `dart analyze --fatal-infos --fatal-warnings` = 0 · tests green (incl. DB-gated).
- [ ] OpenAPI updated for every `/admin/*` + `/reviews/{id}/report`; envelope + pagination respected.
- [ ] Threat model **T17** added; **T14/T15** updated; ROADMAP entry; spec status → Built; cross-linked from pro-kyc.md + consumer-reviews.md.
- [ ] No secrets; new env (`ADMIN_EMAIL`, `ADMIN_PASSWORD`, bcrypt dep) documented in `.env.example`; **OSV** clean for any new dependency. Feature branch + PR; CI green; no Claude attribution.

## 10. Decisions (signed off)
1. **Backend API first**, console UI a later/separate effort. ✓
2. **Slice 1 = foundation (role + trust boundary + audit log) + KYC approval queue + review moderation.** ✓
3. **Single `admin` role now**; sub-roles (super-admin/moderator/support) later. ✓
4. **PR split:** A1 (foundation + KYC) → A2 (review moderation). ✓
5. **Admin auth = email + password (bcrypt), seeded super-admin** from `ADMIN_EMAIL`/`ADMIN_PASSWORD` on first boot; rotating refresh. ✓
6. **Reported reviews stay visible until an admin acts** (report enters the queue; no auto-hide). ✓

## 11. Open questions
_None open._

---

## 12. Slice 2 — Marketplace management, disputes & featured

| | |
|---|---|
| **Status** | **Built** — A3 (provider) · A3b (user) · A4 (disputes) |
| **PRD** | FR-WEB-AD-002 (provider/user mgmt, suspend/ban, support views), FR-WEB-AD-005 (featured), FR-WEB-AD-003 (disputes) |

### 12.1 Decisions (signed off)
1. **Read-only admin support views** — no act-as token; admins view any user/provider + their bookings (+ dispute evidence). True impersonation deferred to when the console UI exists. ✓
2. **Provider suspend** = hidden from discovery + new bookings blocked; **login still works** (manage existing). **Consumer ban** = stricter: login blocked + booking blocked. ✓
3. **Disputes = admin-created case records** on a booking (reason + evidence + resolution + consequence); **no money moves** (no-custody) — resolution is advisory + consequence. No consumer-initiated endpoint yet (gated on app UI). ✓
4. **PR split:** A3 (**provider** suspend/restore + featured + provider support views + discovery/booking enforcement) → A3b (**user** ban + login enforcement + user support views) → A4 (disputes). Kept small/correct given the provider jsonb `data` model. ✓

### 12.2 Data model (migration `0012_marketplace_mgmt`)
- `providers` += `status text not null default 'active'` (active|suspended), `featured boolean not null default false`.
- `users` += `status text not null default 'active'` (active|banned).
- (A4) `disputes` table — `id, appointment_id REFERENCES appointments, opened_by text (admin), status (open|resolved), reason, resolution, created_at, resolved_by, resolved_at`.

### 12.3 Endpoints (A3)
- `GET /admin/providers?status=&q=&page=&pageSize=` · `GET /admin/providers/{id}` (provider + recent bookings) — support views.
- `GET /admin/users?status=&q=&page=&pageSize=` · `GET /admin/users/{id}` (user + their bookings).
- `POST /admin/providers/{id}/suspend` `{reason}` · `/restore` — audited.
- `POST /admin/users/{id}/ban` `{reason}` · `/unban` — audited.
- `POST /admin/providers/{id}/feature` `{featured: bool}` — audited.
- **(A4)** `POST /admin/disputes` `{appointmentId, reason}` · `GET /admin/disputes?status=` · `GET /admin/disputes/{id}` · `POST /admin/disputes/{id}/resolve` `{resolution}` — audited; admin gains read access to the deposit screenshot (extend `DepositService.screenshotUrl` to authorize `role=admin`).

### 12.4 Enforcement
- **Discovery** (`ProvidersRepository.query`) excludes `status='suspended'` and orders **featured first**. `featured` is exposed in the provider DTO; `status` is admin-only.
- **Booking** (`BookingService`) rejects when the provider is `suspended` or the user is `banned` (`provider_suspended` / `account_suspended` → 403/409).
- **Consumer login** (`verifyOtp`) rejects a `banned` user.

### 12.5 Security (extends T17)
All under `/admin/*` (role=admin, deny-by-default); every mutation audited with actor + reason. Suspend/ban/feature are server-owned status transitions (reversible, logged). Support views are **read-only** (no act-as). Disputes never move money. Update **T17** (management + disputes added) and note booking/discovery now honor account status.

### 12.6 Tests
Admin: list/filter + detail (with bookings); suspend → excluded from discovery + booking blocked (login still works); ban → login + booking blocked; feature → featured-first ordering; each mutation writes one audit row; non-admin → 403. Booking/discovery enforcement unit tests. (A4) dispute open/list/resolve + audit + admin screenshot access. DB-gated migration tests.
