# Pro deposit policy management — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro deposit / no-show protection · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Let a salon **set its deposit policy** on the real backend — whether a deposit is required, the percentage, the cancellation window, and the Mobile Money handle the deposit is paid to — replacing `ApiProService.getDepositPolicy` / `updateDepositPolicy`'s delegation to `MockProService`. This is the **last pro mock**.

**Why it's small + high-value:** the policy fields **already** live in the provider record (`depositRequired`, `depositPercentage`, `cancellationWindowHours`, `depositMobileMoneyOperator`, `depositMobileMoneyNumber`), are **already** in the contract's `Provider` schema, and **`BookingService.book` already reads them** as the server authority on deposit/balance/cancellation. So this slice just adds **read/write endpoints** over those fields — and a saved policy immediately governs new bookings. No booking change, no migration.

**In scope:**
- Backend: `GET` + `PUT /providers/{id}/deposit-policy` (provider-authenticated, ownership-scoped). New `ProvidersRepository.updateDepositPolicy` (in-memory + Postgres) + `depositPolicy` / `updateDepositPolicy` on `ProviderCatalogService`, with **server-authoritative validation** (it's money).
- App: the two `ApiProService` deposit-policy methods → the endpoints (`DepositPolicy.fromJson` + operator parse added).
- Contract (`DepositPolicy` schema + paths) + threat model + tests (incl. DB-gated).

**Out of scope:** the actual Mobile Money **payment** + deposit-screenshot verification flow (consumer deposit / Mobile Money spike — separate, PRD top-risk); changing how booking computes the deposit (already correct).

**Build:** one PR.

## 2. UX & flows
No UX change — the pro deposit-policy screen already drives this behind `ProServiceInterface` (toggle + percentage + window + Mobile Money handle, with all four states). This slice makes load/save hit the backend.

## 3. API & contract
Both **provider** token + **ownership** (`account.providerId == {id}` → else 403):
- **`GET /providers/{id}/deposit-policy`** → `DepositPolicy`.
- **`PUT /providers/{id}/deposit-policy`** — body `DepositPolicy` (replace wholesale) → the stored `DepositPolicy`.

`DepositPolicy` (mirrors the Dart model):
```
{ depositRequired: bool,
  depositPercentage: number,        // fraction 0..1 (0.30 = 30%)
  cancellationWindowHours: int,
  mobileMoneyOperator: string|null, // wave | orangeMoney | mtnMoMo | moov
  mobileMoneyNumber: string|null }  // E.164 when present
```
Errors: 400 `invalid_body` / `invalid_input` (bad range/enum/phone, or required-deposit without a Mobile Money handle — see §6), 401, 403, 404 `not_found`, 405.

## 4. Data model
None. The five fields already live in each provider's **`providers.data` jsonb** (note the storage names are `depositMobileMoneyOperator` / `depositMobileMoneyNumber`; the DTO exposes them as `mobileMoneyOperator` / `mobileMoneyNumber`). `updateDepositPolicy` read-modify-writes `data` atomically (the same pattern as `updateGallery`). No migration.

## 5. Architecture & patterns
- **`ProvidersRepository.updateDepositPolicy(providerId, Map fields)`** → returns the stored policy map, or null if the provider doesn't exist. InMemory sets the fields; Postgres `runTx` read-modify-writes `data` (mirrors `updateGallery`).
- **`ProviderCatalogService.depositPolicy` / `updateDepositPolicy`** (deposit policy is salon catalogue management): ownership → read `byId` (map to the DTO) / validate + delegate. Returns `CatalogResult`.
- **Route** `routes/providers/[id]/deposit-policy.dart` (thin): principal → `role==provider` → `GET`→read, `PUT`→parse+validate+write, else 405. Mirrors `gallery.dart` / `availability.dart`.
- DI: no new singleton (reuses `ProviderCatalogService`).
- **Server authority is already wired:** `BookingService.book` reads `depositRequired`/`depositPercentage`/`cancellationWindowHours` from the provider, so a saved policy governs the next booking's `depositAmount` / `balanceDue` / cancellation window with no further change.
- **App:** `getDepositPolicy` → `GET …/deposit-policy` → `DepositPolicy.fromJson`; `updateDepositPolicy` → `PUT …/deposit-policy` (body from the params) → `DepositPolicy.fromJson`. Add `DepositPolicy.fromJson` + a `MobileMoneyOperator` name parser.

## 6. Validation (server-authoritative — it's money)
- `depositRequired`: bool (required).
- `depositPercentage`: number in **0..1**; if `depositRequired`, must be **> 0** (a required-deposit of 0% is meaningless). Reject otherwise → `invalid_input`.
- `cancellationWindowHours`: int **0..720** (≤ 30 days).
- `mobileMoneyOperator`: when present, ∈ { `wave`, `orangeMoney`, `mtnMoMo`, `moov` }.
- `mobileMoneyNumber`: when present, **E.164** (same rule as elsewhere).
- **Cross-field (see open question):** when `depositRequired` is true, the Mobile Money **operator + number are required** (a client paying a deposit needs a destination).
- Unknown fields ignored; the server stores exactly the validated set.

## 7. Security & authz
- Deny by default; provider token + ownership (cross-salon / unlinked → 403).
- All input validated at the boundary; the **server is the authority** — booking derives the deposit from the stored policy, never from the client. The Mobile Money number is the salon's own business contact (not third-party PII); nothing sensitive logged.
- **Threat model:** extend **T12** (catalogue mgmt) to include the deposit policy — ownership + boundary validation, and note that the policy feeds the server-authoritative deposit math in booking.

## 8. Performance
- GET: one `byId`. PUT: one atomic read-modify-write of `data`. Tiny, bounded payload. No N+1.

## 9. Testing plan
- **Service (unit):** `depositPolicy` reads the mapped DTO; `updateDepositPolicy` persists + round-trips; validation (pct out of 0..1, required-with-0%, bad window, bad operator, bad phone, required-without-handle) → invalid_input; cross-salon + unlinked → forbidden; missing provider → not_found.
- **Handler:** `GET` → 200 `DepositPolicy`; `PUT` valid → 200 (persisted, re-GET reflects it); bad body → 400; no token → 401; cross-salon → 403; other verb → 405.
- **Integration (key):** after `updateDepositPolicy(required, 50%)`, a new `BookingService.book` produces `depositAmount = total*0.5` / matching `balanceDue` — proving the policy is the booking authority.
- **Repo (DB-gated):** `updateDepositPolicy` persists into `data` and survives a re-read; unknown provider → null.
- **App:** `getDepositPolicy` GETs + parses; `updateDepositPolicy` PUTs the body + parses; 401 → provider silent refresh; forbidden → error.

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green (incl. DB-gated).
- [ ] OpenAPI: `DepositPolicy` schema + the two paths.
- [ ] Threat model T12 note; ROADMAP entry; spec cross-linked from the route/service/repo + `ApiProService`; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Require a Mobile Money handle when a deposit is required** — if `depositRequired` is true, `mobileMoneyOperator` **and** `mobileMoneyNumber` must be set (else 400). A client paying a deposit needs a destination. ✓
2. **Percentage = fraction 0..1** (0.30 = 30%), **max 100%**, validated `> 0` when required. Trusts the salon to set its own terms. ✓
