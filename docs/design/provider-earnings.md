# Provider earnings detail — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-14 (§12 — the words over the total) |
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

## 12. The words over the total (2026-10-14)

**Owner: « fix the wording for revenus figures ».** The definition (§6,
`completed` only) did not change. The screen's total was labelled « Total »
next to an Accueil that said « Revenus » over a bigger, confirmed + completed
figure for the same day ([provider-dashboard-stats.md](provider-dashboard-stats.md)
§12). The label now says what it counts.

| | App — `earnings_screen` | Web — `/pro/revenus` |
|---|---|---|
| Total card | « Total réalisé » · figure · « Rendez-vous terminés » | the same three lines |
| Empty state, was | « Les paiements encaissés sur cette période apparaîtront ici. » | « Les encaissements de la période choisie apparaîtront ici. » |
| Empty state, now | « Les rendez-vous terminés sur cette période apparaîtront ici. » | « Les rendez-vous terminés de la période choisie apparaîtront ici. » |

- **Label, figure, then what it counts** — the Accueil card's own shape
  (title · value · caption, `bodySmall` / `textTertiary`), so the two
  screens read the same way.
- **Never « encaissé »**: MyWeli does not see a payment (PRD OQ-1, no
  custody); the total is the price of bookings marked « Terminé ». The empty
  state said the opposite under a label that now says « Rendez-vous
  terminés », so it changed with it.
- **Unchanged:** the screen's name « Revenus », the « Analyses » card, the
  tabs, « Aucune transaction », the web page's lead « Vos revenus réalisés
  (rendez-vous terminés). ».
- **Fit:** one more `bodySmall` line in the card. `layout_test` (360/375/390 ×
  1×/2×) and `vertical_fit_test` (the empty « Aujourd’hui » tab on a 780pt
  phone with its safe area, 1× and 2×) stay green.
- **Tests that read the words:** `mobile/test/widget/pro_earnings_wording_test.dart`
  and `web/tests/pro-revenus-wording.test.tsx` read the card's rendered lines
  in order (the app's also checks the caption sits under the figure) and
  that no « encaiss » is on screen; e2e `pro.spec` asserts both lines.
- **Not changed:** App Store screenshot 8 (Revenus) still shows « Total » —
  the owner's call: not reshot.
- **Not changed either: the App Preview film.** The film the owner chose on
  2026-10-14 (« cut 1, and it is good as it is »; PR #590,
  `tool/app_store_preview/README.md` « Version 2 — the film ») was cut from
  takes recorded before this change: its scene S4 (21.867–25.867 s) and its
  poster frame (25.000 s, frame 750) show this card as « Total » ·
  77 000 FCFA, with no line under the figure (seen on the film's built
  `poster.png` and contact sheet, film sha256 `4d945614…`). A build that
  carries this section says « Total réalisé » and adds « Rendez-vous
  terminés » — the « mismatch with the binary » of
  [pro-app-preview.md](pro-app-preview.md) §8. The owner's call: the film is
  not re-cut. Per the same spec's §2, a preview is replaced only with a new
  app version, and its poster frame cannot be changed once approved.
