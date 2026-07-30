# Salon time — the timezone seam (multi-pays slice 1) — design spec

> The first slice of [modules/multi-pays.md](../modules/multi-pays.md) §3:
> every displayed time and every day boundary becomes **the salon's time**
> through one parameterized seam per surface, fed today by a single constant
> `Africa/Abidjan`. Fixes the found device-timezone leaks, adds the viewer
> hint, pins the harnesses, and slips in the currency-parameterized money
> formatters (multi-pays §4.4) since they're the same one-file seam.

| | |
|---|---|
| **Status** | **Built (2026-07-13)** — sign-off same day: §11.a consumer-only hint · §11.b render.yaml pin folded in. Build extras: the app's `earnings_screen` period buckets were the mobile twin of leak 1 (fixed); aligning the mock slot engine to salon instants surfaced flag-mixing bugs in `overlapsBreak`/`artistWorksDuring` (fixed); the calendars' « today » ring now follows the salon day (`currentDay`). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-07-13 |
| **Module / phase** | `multi-pays` (cross-cutting) · readiness now — Wave-2 flip stays deferred |
| **ROADMAP entry** | [ROADMAP.md §1.8](../ROADMAP.md) — multi-pays entry |
| **Skills checked** | myweli-dev-guardrails · myweli-web-guardrails · myweli-backend-guardrails |

## 1. Goal & scope

**The rule (multi-pays §3):** storage stays UTC; **interpretation — display
and day boundaries — is salon time**, never device time. Salon time = the
salon's IANA timezone; until Wave 2 that is the constant **`Africa/Abidjan`**
(= UTC+0 year-round, no DST) behind tz-parameterized helpers. When Bénin/Niger
arrive: the constant becomes a per-salon value fed from the city — **the
helpers don't change**.

**Why now:** two proven product leaks + one display class (§3), plus a real
e2e flake reproduced on a UTC+3 machine (the `revenus` « aujourd'hui » filter
missed a UTC-seeded transaction before local midnight). A viewer in France
(UTC+1/+2) sees shifted times **today** on web.

**In scope:** the web time seam + leak fixes + display timezone pinning; the
mobile salon-time helper + leak fix + sweep; the « heure du salon » viewer
hint (consumer surfaces); harness pinning (Playwright/stub `TZ=UTC`, Render
env); currency-param money formatters (default `XOF`).

**Out of scope (deferred to their waves):** the `cities.timezone` column and
any per-salon timezone value; locality tables; operator catalog; nested SEO
URLs; any backend behavioral change (the API already stores/serves UTC and
computes day gates on UTC = Abidjan days — correct until Wave 2).

## 2. UX & flows

Only one user-visible change — **the viewer hint**:

- **Copy:** « Heures affichées : heure du salon (Côte d'Ivoire) » — one muted
  caption line (tokens, no new styles).
- **Shown when** the viewer's device UTC-offset ≠ the salon's offset **at the
  displayed date** (computed via the seam, not hardcoded ≠ 0).
- **Surfaces (consumer, where a wrong mental clock costs a missed visit):**
  - booking date/time step (app `date_time_selection_screen.dart`, web
    `BookingFlow` time step),
  - booking confirmation (app + web),
  - appointment detail (app + web consumer).
- **Pro surfaces: no hint** — staff are physically at the salon; the journal
  header stays clean. (Open question 11.a if you disagree.)
- Hidden for the ~100 % of CI users whose device is already UTC+0 — zero
  visual change at launch.

## 3. The leak inventory (what gets fixed)

**Proven product leaks:**
1. `web/lib/pro/earnings.ts` `periodRange()` — buckets « aujourd'hui /
   semaine / mois » from **device-local midnight** (`new Date(y, m, d)`). On a
   UTC+3 device at 02:36, "today" is still yesterday → wrong revenue buckets
   (the reproduced e2e flake).
2. `mobile/.../pro_appointment_detail_screen.dart:49` `_isToday()` — compares
   **device-local** calendar components against UTC-parsed dates → « Client
   arrivé » appears/disappears at the wrong hour on a foreign device.
3. `web/lib/format.ts` `formatDateFr`/`formatDateTimeFr` — `Intl.DateTimeFormat`
   without `timeZone` → renders **device time**: a 10:00 Abidjan booking shows
   as 11:00 in Paris. Every web surface displaying times inherits this.

**Sweep candidates (audit each; fix those doing domain day-math or display):**
web `lib/pro/today.ts`, `lib/pro/agenda.ts`, `lib/pro/journal.ts`,
`lib/booking/state.ts`, `components/pro/ManualBookingDialog.tsx`,
`components/pro/ProAppointmentDetailClient.tsx`,
`components/booking/BookingFlow.tsx`,
`components/account/AppointmentDetailClient.tsx`; mobile: the 8 files with
`.day ==`/`isSameDay` logic and the 13 screens/widgets calling
`DateTime.now()` (calendar views, journal, availability, booking date pickers,
mock services). The sweep ends with a grep pin (like R6b's) so new violations
fail review.

## 4. Design — the seams

**Web — new `web/lib/time.ts`:**
- `SALON_TZ = 'Africa/Abidjan'` (the ONLY place the string exists),
- `salonDayKey(d, tz = SALON_TZ)` → `YYYY-MM-DD` via `Intl.DateTimeFormat`
  with `timeZone` (pure, testable),
- `salonDayRange(period, now, tz)` → replaces `periodRange`'s local-midnight
  math (same `{start, end}` contract, UTC instants),
- `isSameSalonDay(a, b, tz)`,
- `salonOffsetDiffers(now, tz)` → drives the hint.
- `format.ts` date/time formatters gain `timeZone: SALON_TZ` (param with
  default — call sites untouched).

**Mobile — new `mobile/lib/core/utils/salon_time.dart`:**
- `kSalonTz` constant; CI = UTC+0 so salon time = the UTC instant's clock —
  helpers (`salonNow()`, `isSameSalonDay(a, b)`, `salonDayOf(dt)`) do UTC
  math, **not** `package:timezone` yet (no dependency for a zero-offset zone;
  the helper bodies swap to an offset lookup at Wave 2 without call-site
  changes — noted in the file header).
- `_isToday` and the swept comparisons route through it; display formatting in
  `formatters.dart` keeps rendering the UTC instant's clock face (never
  `.toLocal()` for domain times).

**Formatters (the §4.4 freebie):** `formatFcfa(amount, {currency = 'XOF'})`
web + mobile equivalents — signature change only, zero call-site edits.

**Backend:** no behavioral change. Add the one-line convention to
[BACKEND.md §2](../BACKEND.md) (done in this PR): *UTC storage; day
boundaries/interpretation are salon time — today `Africa/Abidjan` = UTC, so
existing UTC day-math is already correct; the seam is the convention.*

**Harness & infra pinning:**
- Playwright `use.timezoneId: 'UTC'` + the e2e stub launched with `TZ=UTC`
  (kills the date-boundary flake class deterministically),
- Render service env `TZ=UTC` in `render.yaml` (defensive — Docker images are
  UTC by default; pin it so it's a decision, not a default),
- unit tests keep NON-pinned coverage: the tz-parameterized helpers are tested
  with simulated foreign-device times (that's where the class stays guarded).

## 5. Architecture & patterns
Pure helpers in `core/utils/` (mobile) and `lib/` (web) — no new layers, no
DI, no interface changes. The seam files carry a
`// Design: docs/design/timezone-salon-time.md` header and are listed in
multi-pays §9 as the only legal home for timezone facts.

## 6. Security & authz
No new endpoints, no authz change, no threat-model delta (day-gate authority
stays server-side; T41/T43's « UTC (Abidjan) » day boundaries are unchanged
and now named by the convention).

## 7. Performance
`Intl.DateTimeFormat` instances hoisted/memoized (they're construction-heavy);
mobile helpers are arithmetic only. No budget impact.

## 8. Testing plan
- **Web unit:** `salonDayRange` under simulated UTC+3 / UTC−5 device clocks
  (the flake's exact shape: 02:36 MSK ∈ « aujourd'hui » Abidjan); formatter
  output pinned to Abidjan clock faces regardless of process TZ; hint
  predicate true/false matrix.
- **Mobile unit/widget:** `_isToday` replacement across the midnight boundary
  both directions; hint visibility on the booking time step with an injected
  foreign offset; the sweep grep pin.
- **e2e:** suite runs pinned `TZ=UTC` (config change is itself asserted by a
  smoke that seeds a 23:30 UTC booking and checks the « aujourd'hui » bucket).
- **Gates:** analyze 0 · typecheck/lint/build · full suites green on both
  surfaces.
- **Test date hygiene (rule, applies suite-wide):** no fixed calendar dates
  that the run date can catch up with — a "today"-sensitive test either
  injects a clock or computes a strictly-future date (the backend
  `journal_test.dart` « fixed future Monday » `2026-07-13` detonated on
  2026-07-13 and failed every PR for one day; fixed alongside this spec —
  the mobile twin was R6b's `pro_appointment_detail_arrive_test`).

## 9. Rollout & scope discipline
One PR (web + mobile + config + docs cross-links) — the slice is small and
the rule is one coherent change. Mock services stay default; no flag needed
(behavior at UTC+0 is identical for CI users — the change is correctness on
foreign devices + determinism in CI).

## 10. Definition of done
- [x] analyze 0 · format clean · web typecheck/lint/build · all tests green
      (527 mobile · 280 web unit · 66 e2e — the e2e ran green on a UTC+3
      machine, the flake's original habitat).
- [x] The leaks + display class fixed (incl. the app `earnings_screen` twin);
      sweep done + grep pins added (web `tests/time-pin.test.ts`, mobile
      `test/unit/salon_time_pin_test.dart`).
- [x] Hint live on the consumer surfaces (booking time step, confirm/recap,
      appointment detail — app + web); French copy; tokens only.
- [x] Harnesses pinned (`timezoneId: 'UTC'` + webServer `TZ`, CI top-level
      `TZ: UTC`, `render.yaml` `TZ=UTC`).
- [x] Formatters take `currency` (default XOF; XOF/XAF → « FCFA », and the
      app's money display aligned from « XOF » to « FCFA »).
- [x] Spec status → Built; ROADMAP + multi-pays §3 refreshed; seam files
      cross-linked. Task chip `task_a491ec55` (stub date-flake) dismissed as
      superseded.

## 11. Open questions
- **(a)** Hint on pro surfaces too (journal/agenda header)? Proposed: no —
  staff are at the salon; revisit if owners travel-manage.
- **(b)** OK to fold the `render.yaml` `TZ=UTC` env pin into this PR (infra
  file, one line)? Proposed: yes.
