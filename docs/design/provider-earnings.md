# Provider earnings detail — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro earnings · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Put the pro **earnings detail** on the real backend — the realized-earnings total + the per-appointment **transactions** list behind the dashboard's revenue — replacing `ApiProService.getEarnings`'s delegation to `MockProService`.

**In scope:**
- Backend: `GET /providers/{id}/earnings?startDate=&endDate=` (provider-authenticated, ownership-scoped) → `EarningsData`, computed by a new `ProviderEarningsService` over the existing `AppointmentRepository.listForProvider` (no migration, no repo change).
- App: `ApiProService.getEarnings` → the endpoint (`EarningsData.fromJson` added); the rest of `ProServiceInterface` unchanged.
- Contract (`EarningsData` + `EarningsTransaction` schemas + the path) + threat model + tests.

**Out of scope:** payouts / money movement (no custody — PRD OQ-1); deposit policy; gallery; pro reschedule. Real payment-provider reconciliation (deferred).

**Build:** one PR (backend endpoint + app swap) — a single read-only endpoint + one app method.

## 2. UX & flows
No UX change — `earnings_screen` already renders this behind `ProServiceInterface` (total + transactions list with its loading/empty/error/success states).

## 3. API & contract
`GET /providers/{id}/earnings?startDate=&endDate=` — **provider** token + **ownership** (`account.providerId == {id}` → else 403). Optional ISO `startDate`/`endDate` query params (inclusive); absent → all-time.

Response = **`EarningsData`** (mirrors the Dart model):
```
{ totalEarnings: number,
  transactions: [ { id, appointmentId, amount:number,
                    date:date-time, status:string } ] }
```
Errors: 400 `invalid_input` (unparseable date), 401 `unauthorized`, 403 `forbidden`, 405.

## 4. Data model
None. Reads `listForProvider(id)` (all statuses; has `status`, `totalPrice`, `appointmentDate`, `id`). No migration.

## 5. Architecture & patterns
- **`ProviderEarningsService`** (new; no dart_frog/SQL): resolves `account.providerId` via `ProviderAuthRepository.accountById`, enforces ownership (403), reads `listForProvider`, filters to **`completed`** in the date range, and returns `{ totalEarnings, transactions }` — mirrors `ProviderDashboardService` (read-only provider reporting, ownership-scoped).
- **Route** `routes/providers/[id]/earnings.dart` (thin): principal → require `role==provider` → parse/validate `startDate`/`endDate` → delegate → shape. `GET` only (405 otherwise).
- DI + middleware provide the service.
- **App:** `ApiProService.getEarnings` → `_authed.send(GET …/earnings?…)` (provider session + silent refresh) → `EarningsData.fromJson`. Add `EarningsData.fromJson` + `EarningsTransaction.fromJson`.

## 6. Earnings definition (server-authoritative; UTC)
From `listForProvider`, keep appointments with **`status == completed`** whose `appointmentDate` falls in `[startDate, endDate]` (inclusive; missing bound = open). Then:
- `totalEarnings` = Σ `totalPrice` of those.
- `transactions` = those, **newest first**, each `{ id: "transaction_<appointmentId>", appointmentId, amount: totalPrice, date: appointmentDate, status: "completed" }`.

> **Earnings = `completed` only (realized money)** — deliberately narrower than the dashboard's *revenue* (confirmed + completed, forward-looking). The dashboard answers "how much is booked/earned this period"; earnings is the ledger of money actually earned. ← see open question.

## 7. Security & authz
- Deny by default; provider token + ownership (403 cross-salon/unlinked). Read-only; no money movement.
- Validate `startDate`/`endDate` parse (else 400); no other input. Amounts are PII-adjacent business data — scoped to the owner; nothing sensitive logged.
- **Threat model:** covered by **T5** (provider reads scoped to own salon) — extend the note to include earnings.

## 8. Performance
- One `listForProvider(id)` read + in-memory filter/fold; indexed by `provider_id`. The **date range bounds** the result; with no range it's the salon's all-time completed set (bounded for V1). Pagination is a future refinement if a salon's history grows large (the `EarningsData` shape — total + list — would need to change then). No N+1.

## 9. Testing plan
- **Service (unit):** totals + transactions over a fixture (completed in range counted; pending/confirmed/cancelled excluded; out-of-range excluded; newest-first; transaction shape); ownership mismatch + unlinked → forbidden.
- **Handler:** `GET` success → 200 `EarningsData`; date filter honored; bad date → 400; no token → 401; cross-salon → 403; non-GET → 405.
- **Contract:** response matches `EarningsData`/`EarningsTransaction`.
- **App:** `ApiProService.getEarnings` hits `/providers/{id}/earnings` with the range query, parses; 401 → provider silent refresh; forbidden → error.
- DB-gated: not required (no new repo method/SQL; `listForProvider` already DB-tested).

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green.
- [ ] OpenAPI updated (`EarningsData` + `EarningsTransaction` + path); Dart models gain `fromJson`.
- [ ] Threat model T5 note; ROADMAP entry; spec cross-linked from the route/service + `ApiProService`; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Earnings = `completed` only** (realized money) — intentionally narrower than the dashboard's revenue (`confirmed`+`completed`). ✓
2. **Date filtering** — inclusive `[startDate, endDate]` on `appointmentDate`, both optional (all-time if omitted). Pagination deferred (the range bounds the result for V1; the `EarningsData` shape would change if needed later). ✓
