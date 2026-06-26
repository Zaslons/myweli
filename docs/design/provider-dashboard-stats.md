# Provider dashboard stats — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro dashboard · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Put the **pro dashboard stats** on the real backend: a single server-computed aggregate of the salon's appointments (`DashboardStats`), replacing `ApiProService.getDashboardStats`'s delegation to `MockProService`. The pro home/dashboard screen then shows real numbers when `useApiBackend` is on.

**In scope:**
- Backend: `GET /providers/{id}/dashboard` (provider-authenticated, ownership-scoped) → `DashboardStats`, computed by a new `ProviderDashboardService` over the existing `AppointmentRepository.listForProvider` (no repo change, no migration).
- App: `ApiProService.getDashboardStats` → the endpoint (`DashboardStats.fromJson` added); the rest of `ProServiceInterface` unchanged.
- Contract (`DashboardStats` schema + the path) + threat model + tests.

**Out of scope:** earnings detail, gallery, deposit policy, manual booking, pro reschedule (still mock). Real "earned payout" accounting (no custody — PRD OQ-1).

**Build:** **one PR** (backend endpoint + app swap) — it's a single read-only endpoint + one app method, low-risk; the backend-first discipline is satisfied within the PR (contract + endpoint land with the app consumer). ← flag if you'd rather split.

## 2. UX & flows
No UX change — swap behind `ProServiceInterface`; the dashboard screen keeps its loading/empty/error/success handling. (It already renders these six numbers from the mock today.)

## 3. API & contract
`GET /providers/{id}/dashboard` — **provider** token + **ownership** (`account.providerId == {id}` → else 403; unlinked → 403). Mirrors the catalogue/appointment authz.

Response = **`DashboardStats`** (new schema, mirrors the Dart model field-for-field):
```
{ todayAppointments:int, pendingRequests:int,
  todayRevenue:number, weekRevenue:number, monthRevenue:number,
  totalAppointments:int }
```
Errors: 401 `unauthorized`, 403 `forbidden`, 405.

## 4. Data model
None. Reads `AppointmentRepository.listForProvider(id)` (all statuses; already returns `status`, `totalPrice`, `appointmentDate`). No migration.

## 5. Architecture & patterns
- **`ProviderDashboardService`** (new; no dart_frog/SQL): resolves `account.providerId` via `ProviderAuthRepository.accountById`, enforces ownership (403), reads `listForProvider`, computes the six stats, returns `(ok, error, data)` — mirrors `ProAppointmentService` / `ProviderCatalogService`.
- **Route** `routes/providers/[id]/dashboard.dart` (thin): principal → require `role==provider` → delegate → shape. `GET` only (405 otherwise).
- DI + middleware provide the service.
- **App:** `ApiProService.getDashboardStats` → `_authed.send(GET …/dashboard)` (provider session + silent refresh) → `DashboardStats.fromJson`. Add `DashboardStats.fromJson` to the model.

## 6. Stat definitions (server-authoritative; UTC — Abidjan is UTC+0)
Windows: **today** = the UTC calendar day; **week** = Monday-based (Mon 00:00 → +7d); **month** = calendar month. Computed from `listForProvider`:
- `todayAppointments` — bookings whose `appointmentDate` is **today**, **excluding `cancelled`** (signed off).
- `pendingRequests` — `status == pending` (any date).
- `todayRevenue` / `weekRevenue` / `monthRevenue` — Σ `totalPrice` of bookings in that window with status ∈ **{`confirmed`, `completed`}** (signed off — fixes the mock's drop-off of completed bookings).
- `totalAppointments` — all of the salon's bookings (any status).

## 7. Security & authz
- Deny by default; provider token + ownership (403 on mismatch/unlinked). Read-only — no mutation, no money movement.
- No new input beyond the path id (validated by ownership). No secrets; nothing sensitive logged.
- **Threat model:** extend **T5** (provider reads scoped to own salon) — the dashboard is another provider read scoped by `providerId`.

## 8. Performance
- One `listForProvider(id)` read + in-memory fold (a salon's appointment count is bounded for V1). No N+1. Indexed by `provider_id`. (If a salon's history grows large, a future refinement is SQL aggregation / a cached counter — noted, not needed now.)

## 9. Testing plan
- **Service (unit):** computes each stat over a fixture set (today/week/month windows, status filters); ownership mismatch + unlinked → forbidden.
- **Handler:** `GET` success → 200 `DashboardStats`; no token → 401; cross-salon → 403; non-GET → 405.
- **Contract:** response matches the `DashboardStats` schema.
- **App:** `ApiProService.getDashboardStats` hits `/providers/{id}/dashboard`, parses; 401 → provider silent refresh; forbidden → error; not-connected → fail fast.
- DB-gated: not required (no new repo method/SQL); the existing `listForProvider` DB tests cover the read.

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green.
- [ ] OpenAPI updated (`DashboardStats` + path); Dart model gains `fromJson`.
- [ ] Threat model note; ROADMAP entry; spec cross-linked from the route/service + `ApiProService`; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Revenue basis = `confirmed` + `completed`** in each window. ✓
2. **`todayAppointments` excludes `cancelled`.** ✓
3. **Build = one PR** (backend endpoint + app swap). ✓
