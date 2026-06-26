# Consumer deposit / Mobile Money flow — design spec

| | |
|---|---|
| **Status** | B1 (backend) Approved — building · B2 (app) next |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Payments & deposits · V1 (PRD §6.1 custody model, §9.4, FR-PAY-001…005) — **top risk** |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ + myweli-dev-guardrails (deposit/accept UX) |

## 1. Goal & scope

Complete the **no-custody deposit flow** on the real backend, **securely**. Per PRD §6.1 (binding) + §9.4: Myweli **never holds money** — the client pays the salon's Mobile Money **directly** (Wave deep-link / copyable number+amount), **attaches a screenshot** as proof, and the salon **views it and confirms** (accept → `confirmed`). Deposits are **opt-in per salon**; refunds are salon↔client. **No aggregator** in V1.

**This is mostly hardening + wiring** — most of the flow already exists. The audit:

| Already built | Gap this slice closes |
|---|---|
| Deposit **policy** (%, MoMo handle), server-authoritative | — |
| Booking computes `depositAmount`/`balanceDue`, stores `depositScreenshotUrl`, `pending` | — |
| Consumer **deposit sheet**: Wave deep-link, "Copier", attach screenshot, book | screenshot goes to the **public** bucket (✗) + uses the **mock picker** (✗ in API mode) |
| Salon **sees** the screenshot on accept; **accept = confirm receipt** | salon renders a **public URL** (✗) |
| — | **no "pay later"** (attach a screenshot to an already-pending booking) |

**In scope:**
- **B1 (backend):** a `deposit` upload purpose (**consumer-authenticated, private**, prefix `deposit/{userId}`); **signed-GET** viewing (`StorageService.presignGet`) so only the consumer + the owning salon can see the screenshot; `POST /appointments/{id}/deposit` (pay-later submit) + `GET /appointments/{id}/deposit-screenshot` (signed URL); `depositScreenshotUrl` becomes a **private key**.
- **B2 (app):** the deposit sheet uploads via the **private** path with the **real picker**; the consumer preview + the pro accept screen fetch the **signed URL** to display; a pay-later "submit deposit" entry from my-bookings.

**Out of scope:** real Mobile Money **aggregator** / one-tap pay (deferred, OQ-1); in-app **full payment**, wallet, tipping (V2/V3); **automated refunds** (salon↔client — Myweli surfaces the policy only, FR-PAY-005); Myweli-issued receipts (no Myweli-side transaction).

## 2. UX & flows
No structural change. Book → (deposit on) **deposit sheet**: "Acompte X · Solde Y", **Payer avec Wave** / copy number, **attach screenshot** (real picker → private upload), **"J'ai payé"** → booking `pending`. The salon's accept screen shows the screenshot (signed) → **accept** → `confirmed`, both notified (notifications deferred). **Pay-later:** a pending deposit-booking in *My bookings* offers "Envoyer l'acompte" → the same sheet → `POST …/deposit`. Cancellation policy stays display-only (FR-APPT-003/005). French copy; all four states already exist.

## 3. API & contract
- **`POST /uploads/sign`** gains **`purpose=deposit`** — **consumer** (`user`) token → presigns into the **private** bucket, prefix `deposit/{userId}` (server-built from the token), returns the `key` only (images: jpeg/png/webp). (gallery/kyc remain provider-only; the route gates role by purpose.)
- **`POST /appointments/{id}/deposit`** — **consumer owner** (`appointment.userId == sub`); body `{ "screenshotKey": "deposit/{userId}/…" }` (validated under the caller's prefix); the booking must be `pending`; sets `depositScreenshotUrl = key`. → 200 the updated `Appointment`. (Booking can still include the key inline at create; this enables pay-later/replace.)
- **`GET /appointments/{id}/deposit-screenshot`** — authorized to the booking's **consumer** (`userId == sub`) **or** the booking's **salon** (provider account's `providerId == appointment.providerId`); returns `{ "url": "<short-lived signed GET URL>" }`. 404 if no screenshot.

Errors: 400 `invalid_input` (foreign/missing key, wrong content-type), 401, 403, 404, 405. No new money endpoints (Myweli moves nothing).

## 4. Data model
None new. `appointments.deposit_screenshot_url` now holds a **private object key** (not a public URL). The deposit "intent" is the appointment itself (`depositAmount` + `depositScreenshotUrl` + `pending` status); "receipt confirmed" = the salon's `accept` (`pending → confirmed`) — no separate payment entity (matches FR: no Myweli-side transaction). Screenshots live in a **dedicated private bucket `R2_DEPOSIT_BUCKET`**, kept apart from `R2_KYC_BUCKET` so the two can have independent retention (deposits are transient → can auto-expire; KYC is retained for compliance), credential scoping, and blast-radius isolation. Bucket selection is a typed `StorageBucket { public, kyc, deposit }`.

## 5. Architecture & patterns
- **`StorageService.presignGet({key, ttl})`** → a short-lived **signed GET** URL for a private-bucket object. `R2StorageService`: AWS **SigV4 query-string presign** (GET, `X-Amz-*` params, `SignedHeaders=host`, `UNSIGNED-PAYLOAD`) — in-house with `crypto`. `FakeStorageService`: a deterministic fake URL.
- **`UploadSigningService.sign`** learns `purpose=deposit`: prefix `deposit/{accountId}` where `accountId` is the consumer's `sub` (no provider lookup), `private: true`, image content-types. The `/uploads/sign` route gates role **per purpose** (`deposit` → `user`; `gallery`/`kyc` → `provider`).
- **`DepositService`** (new; `AppointmentRepository` + `ProviderAuthRepository` + `StorageService`):
  - `submit(userId, appointmentId, key)` → `byId`; owner + `pending` + key-prefix (`deposit/{userId}/`) checks → `update(depositScreenshotUrl)`.
  - `screenshotUrl(appointmentId, {sub, role})` → load + authorize (consumer owner **or** owning salon) → `presignGet(key)` → `{url}` (or `not_found`).
- **`AppointmentRepository.update`** handles a `depositScreenshotUrl` change (in-memory + Postgres `SET deposit_screenshot_url`).
- **Routes** (thin): `routes/appointments/[id]/deposit.dart` (POST) + `routes/appointments/[id]/deposit-screenshot.dart` (GET); `/uploads/sign` extended. DI + middleware provide `DepositService`.
- **App (B2):** `ApiAppointmentService` gains `uploadDepositScreenshot(source)` (private upload → key) + `submitDeposit(id, key)` + `depositScreenshotUrl(id)` (signed GET). The deposit sheet + pro accept screen use them; the consumer preview + pro screen render the signed URL.

## 6. Security & authz (this is money-adjacent PII)
- **No custody** — the server never moves or holds funds; it records the booking + the screenshot key + status. (PRD §6.1.)
- Deposit uploads are **consumer-only, self-scoped** (key prefix `deposit/{sub}`); submit re-checks the key is under the caller's prefix (no foreign key). Screenshots are **private** (no public URL ever); viewing is a **short-TTL signed-GET** restricted to the booking's consumer **or** its salon.
- `depositAmount` stays **server-computed** from the policy (client never sets it). Wave links carry recipient+amount only; the client authorises in their own app.
- **Threat model:** new **T16** (deposit screenshot) — private bucket + unguessable key + signed-GET (owner consumer or owning salon only) + no bytes through the API + no custody; amount server-authoritative.

## 7. Performance
- `presignGet`/`sign` are pure HMAC (sub-ms). Bytes go client → storage directly. Submit = one `byId` + one `update`. View = one `byId` + a sign. No N+1.

## 8. Testing plan
- **Storage:** `R2StorageService.presignGet` structure (host, `X-Amz-Algorithm/Credential/Date/Expires/SignedHeaders`, 64-hex signature, private bucket); Fake returns a usable URL. `purpose=deposit` → private key `deposit/{sub}/…`, no public URL, consumer-scoped.
- **DepositService:** submit (owner + pending + key-prefix; foreign key / non-owner / non-pending → error); `screenshotUrl` authorizes consumer owner + owning salon, rejects a stranger, 404 when no screenshot.
- **Routes:** `/uploads/sign` deposit → consumer 200 / provider 403; `POST …/deposit` → 200 / not-owner 403 / 400 bad key; `GET …/deposit-screenshot` → 200 {url} / stranger 403 / 404 none / 401.
- **App (B2):** deposit upload (sign deposit → private POST → key); book/submit send the key; both surfaces fetch the signed URL; real picker gated by `useApiBackend`.

## 9. Definition of done (per PR)
- [ ] `dart format` clean · `dart analyze` 0 · tests green (incl. DB-gated where relevant).
- [ ] OpenAPI: the deposit upload purpose + `/appointments/{id}/deposit` + `/appointments/{id}/deposit-screenshot`.
- [ ] Threat model **T16**; ROADMAP entry; spec cross-linked; status → Built.
- [ ] No secrets; new `R2_DEPOSIT_BUCKET` (private) via env + `.env.example`. Feature-branch + PRs; CI green; no Claude attribution.

## 10. Decisions (signed off)
1. **Private + signed-GET** for the screenshot (not public). ✓
2. **Pay-later** `POST /appointments/{id}/deposit` (book now, attach proof later); booking-with-key still works. ✓
3. **Two PRs** — B1 backend → B2 app. ✓
4. **Dedicated private bucket** `R2_DEPOSIT_BUCKET`, separate from KYC (independent retention / credential scope / blast radius; R2 has no per-bucket fee). Bucket selection is a typed `StorageBucket` enum. ✓
5. Carried in (binding): **no custody**; Wave deep-link / copy-number; **opt-in per salon**; refunds salon↔client; **no aggregator** (V1). ✓

## 11. Open questions
_None open._
