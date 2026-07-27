# mobile-a10-clock — the clock seam, and a register row copied from a comment that was wrong (A10)

**Status:** Done (2026-07-27). **Surface:** `mobile/` — the clock, and
three pro screens that could not be photographed. **Design system:**
[SYSTEM.md §18](SYSTEM.md#18-market-data--salon-time) ·
[§20/§20.1](SYSTEM.md#20-enforcement) ·
[§21](SYSTEM.md#21-the-known-violations-register) row 23.
**Related spec:** [timezone-salon-time.md](timezone-salon-time.md) §5 — the
seam's shape, and §"Test date hygiene", which is A10's charter.
**Roadmap:** design-system programme, mobile A-series slice A10.

## Goal & the debt

The pro dashboard and journal read the wall clock on a render path, so a golden
of either would be *"a picture of the day it was taken: green on Tuesday, red on
Wednesday"*. §20.1 lists this as one of **"two things a golden cannot pin"**;
A8 halved the first bullet, and A10 closes the second.

## ⚠️ Row 23 is a copy of a code comment, and inherited its errors

The register text is lifted almost verbatim from
`pro_screens_golden_test.dart:29-46`. Measured against the code, **two of its
three specifics are wrong**, and the third names the wrong mechanism.

| The row says | Measured |
|---|---|
| `MockProService.getDashboard()` buckets by weekday | **There is no `getDashboard()`.** It is `getDashboardStats(String providerId)` — `pro_service_interface.dart:129`, `mock_pro_service.dart:264`, `api_pro_service.dart:369` |
| "…so its **weekly stat cards** change value depending on which day CI runs" | `weekday` reaches exactly one value, `weekRevenue` — and **`weekRevenue` is never rendered.** Grep: computed at `mock_pro_service.dart:292`, carried at `pro_service_interface.dart:20`, read by no screen. The dashboard renders `todayAppointments`, `pendingRequests`, `todayRevenue`, `monthRevenue` (`dashboard_screen.dart:236,246,264,278`). **The card the row describes does not exist** |
| the journal "prints TODAY's date into its header" | `pro_journal_screen.dart:492` renders `isToday ? 'Aujourd’hui' : Formatters.formatDate(…)`, and on the default path `isToday` is always true — **the header is stable.** The flake is the **week strip** (`:536-537`): `monday = selected.subtract(selected.weekday - 1)`, seven pills each printing `${d.day}` (`:590`), with the selected pill moving one slot right every day and wrapping on Monday. Seven numbers change daily, plus the highlight position |

The dashboard's real flake is **monthly and rare**: `appointment1` is seeded at
`now + 2d`, so `monthRevenue` flips between 5 000 and 0 on the last two days of
each month.

**None of this means the row was pointless** — both screens genuinely cannot be
goldened. It means the row could not have been used to write the fix, and a
slice that trusted it would have gated a card that does not exist.

## The row is also a large undercount

Un-goldenable, all reading the clock on a render path, none mentioned:

- **`earnings_screen.dart:53,60,65`** — period buckets, Monday-anchored off
  today's weekday. **This is the screen the row's "buckets by weekday"
  description actually fits.**
- `appointment_list_screen.dart:87,97` · `appointment_calendar_view.dart:39`
  (a whole month rendered around today) · `pro_manual_booking_screen.dart:110,
  123,137` · `availability_screen.dart:253-255,609` ·
  `pro_subscription_screen.dart:257-259` (already worked around in the golden
  file: *"a trial would print a countdown, and a countdown is a clock in the
  picture"*).
- And **inside two goldens that already exist**:
  `provider_detail_screen.dart:443` (`consumer_provider_detail`) and
  `booking_hub_screen.dart:97,339,746-747` (`consumer_booking_hub`). Both are
  stable **by luck** — `MockData` seeds at offsets from *now*, so the relative
  comparisons land the same way whenever CI runs. One absolute date in the seed
  away from a daily failure.

## The measurement that reframes the work

`DateTime.now()` in `mobile/lib` is **106**, and that grep is the wrong
instrument: **19 render-path sites contain no `DateTime.now()` token at all** —
they call `salonToday()` / `salonNow()` with `now:` omitted. True render-path
total: **38 sites across 16 product files**, plus 4 root reads inside the seam.

| Bucket | Count |
|---|---|
| render path (direct token) | 19 |
| render path (via the seam, no token) | 19 |
| `services/mock/` data generation | 71 |
| genuinely non-visual (request bodies, cache expiry, `fromJson` fallbacks, ids) | 12 |

**The leverage point:** routing the 4 reads inside `core/utils/salon_time.dart`
through the seam makes **19 of the 38 deterministic in one edit, with zero
call-site churn**. `salonNow()` is also the only helper there **without** a
`now:` parameter — `salonToday`, `salonDayBoundsUtc` and
`deviceOffsetDiffersFromSalon` all have one.

## ⚠️ The seam shape reversed, and why

The first decision was **`package:clock`**, on the argument that zone-scoped
injection gives testability with no global mutable state. Measured, zones miss
exactly what this slice needs:

- **`flutter_test` already overrides the ambient clock.**
  `AutomatedTestWidgetsFlutterBinding.runTest` builds a `FakeAsync` whose clock
  is seeded from `clock.now()` — the *real* wall clock at test start. So
  `clock.now()` inside a widget test is already non-deterministic.
- **Timers capture their zone at creation, not at firing** (`fake_async.dart`
  `createTimer` → `_zone.runUnaryGuarded`). The mocks' 300 ms
  `AppConstants.mockDelay` and `pro_screens_golden_test._pumpPro`'s `runAsync`
  sign-in both create work outside any body-level `withClock`.
- **`MockData.appointments` is `static final`** — memoised per isolate at first
  touch, in whatever zone touched it first. No zone can reach it afterwards.
- **`import 'package:clock/clock.dart'` in `lib/` without a pubspec entry trips
  `depend_on_referenced_packages`** → an *info* → **CI red** under
  `--fatal-infos`. `clock` is transitive-only today.

So the seam is a **function pointer**: `AppClock.now()` backed by an overridable
`DateTime Function()`. It reaches field initializers, timers and `static final`
seeds alike, because it does not depend on which zone the caller is in. It also
*is* the house idiom — `salon_time.dart`'s four helpers and
`Formatters.formatRelative` already take `{DateTime? now}` defaulting to the
ambient source.

## The house pattern this matches

From `salon_time.dart` (MP2), `app_locale.dart` (A9), `reduce_motion.dart` (A8):

1. A file in `core/`, **free functions — no DI, no interface, no provider**
   (`timezone-salon-time.md` §5 says so outright).
2. **Idempotent init tests never have to call.** `initSalonTime()`'s lazy
   self-call from `locationOf` is the standard: the product path and the test
   path are the same code.
3. **Injection is an optional named parameter** defaulting to the ambient
   source, never a mandatory constructor argument.
4. Called by the three roots **and every test shell** — which after A9 provably
   means `wrapApp` **and** `goldenApp` **and** `_pumpPro`, because
   **`test/golden/` does not import `pump_app.dart`**. A9's pin had to widen its
   glob for exactly this reason.
5. **The pin globs, never lists**, carries an `isNotEmpty` guard against a
   wrong-cwd vacuous pass, and uses a named `allow:` list.

## Two latent §18 violations, fixed while here

- `pro_journal_provider.dart:80` — `todayKey => keyOf(DateTime.now())` reads the
  **device's** now, not the salon's. It happens to work because `keyOf` converts,
  but §18 forbids the call-site shape.
- `mock_pro_service.dart:271` — `DateTime(today.year, today.month, today.day)`
  from device-local now computes a **device-local day boundary**, which §18
  forbids outright.

Neither is caught by `salon_time_pin_test.dart` today, because it sweeps
`.toLocal(`, `DateFormat(` and `'Africa/Abidjan'` — never the clock.

## Tests & gates — written first, watched fail, then swept

**A gate that pins "today" passes on the day it is written.** So the determinism
gate pumps each screen under **two different frozen dates** and asserts what must
differ does and what must not doesn't — the journal's week strip moves, the
dashboard's four cards don't.

**The lockstep set.** 12 subscription/trial fixtures and 3 slot generators in
`mobile/test/` build dates from raw `DateTime.now()` and are compared against
`SalonSubscription`'s own `DateTime.now()` (`salon_subscription.dart:58`).
Sweeping `lib/` alone decouples the two clocks and the day counts go wrong
**silently, not loudly**. They move in the same commit.

**One test opts out on purpose.** `salon_time_test.dart:104` asserts
`salonNow()` is within 5 s of the real clock. That is the correct test to keep —
it is the only thing asserting the seam's default *is* the wall clock.

## What this slice will NOT do

- **No `flutter_test_config.dart` process-wide freeze.** It would kill the opt-out
  test above and make every suite's clock a hidden global.
- **`screens/provider/features/booking_journal_screen.dart` is not touched** —
  three render-path clock reads, but **zero references outside its own
  declaration**; §22 shelves it.
- **Only three goldens.** `pro_dashboard`, `pro_journal`, `pro_earnings`. The
  seam and the pin make the remaining five goldenable; taking those pictures is a
  later slice's cheap win, and eight new baselines in one PR is more than can be
  eye-reviewed honestly — §20.1's own warning.

## ⚠️ Four things this spec got wrong, found by building it

Recorded here rather than silently corrected, because each was an argument this
document made confidently before anything was measured.

1. **One of the two "latent §18 violations" was not one.**
   `pro_journal_provider.todayKey` was `keyOf(DateTime.now())`, which §"Two
   latent §18 violations" called a call-site violation. `keyOf` is
   `salonDayKey`, which converts the *instant* — so the raw clock read was the
   whole defect and the sweep is the whole fix. The genuinely fragile shape in
   that file is the other one, `keyOf(_selectedDate)`, which converts an
   already-converted salon date; it is correct for every timezone at or east of
   UTC, which is all of them Myweli serves.

2. **The "app-wide pin" would have been the wrong instrument.** Sweeping `test/`
   for `DateTime.now()` bans **38 sites**, nearly all legitimate relative
   fixtures, and pushes authors toward absolute dates that rot — while missing
   nothing, because *an unfrozen test reading the wall clock is correct*. The
   hazard is the **mix**: a file that freezes AND reads. That is what shipped.

3. **Three goldens was one too few.** `MockData` seeds `provider1` at `now+2d`,
   `now-10d`, `now-7d` — never today — so the journal's default day is the empty
   state, and a single picture of it pins a placeholder while the timeline rows,
   the status chips and the artist filter go unphotographed. `pro_journal_day`
   is the fourth, and it also catches the `isToday` branch row 23 accused —
   « vendredi 13 mars 2026 » — which had never appeared in any test.

4. **`_FixedRoster` was not buying what it claimed, and neither was the first
   version of this spec's determinism proof.** The plan said "confirm the bytes
   are identical". Run, that is only half right: 23 of 26 are identical, and the
   three that move are *supposed* to. A clock-bearing golden that comes back
   byte-identical under a different freeze is ignoring the freeze. The proof is
   "identical, **or** differing only in rendered dates" — and it caught a real
   bug on the first run: `pro_journal_day` tapped the literal `'13'`, which does
   not exist in the week of 22 September 2027.

## The determinism proof, run

Every baseline regenerated under two frozen instants eighteen months apart —
**11 Mar 2026** (`kFixedNow`) and **22 Sep 2027** — in the pinned Linux image.

| Result | Count | Meaning |
|---|---|---|
| byte-identical | **23 / 26** | no hidden wall-clock read leaks in |
| differ, only in rendered dates | 2 (`pro_journal`, `pro_journal_day`) | the strip and header follow the frozen clock and nothing else |
| differ, in row order | 1 (`pro_team`) | §21 row 39 — `invitedAt` mixes relative and absolute seeds |

Both runs: **26 passing**.

### ⚠️ "Identical" is only half a proof, and a third run was needed

`pro_dashboard` came back byte-identical across those two instants — and that
does **not** prove the freeze reached it. Both dates sit mid-month, so the
appointment seeded at `now + 2d` lands in the same month either way and
`monthRevenue` is 5 000 in both. An unfrozen dashboard photographed twice on the
same afternoon would have produced exactly the same result.

So a third run, frozen on a **month edge** — **30 Sep 2027**:

| | 11 Mar 2026 | 30 Sep 2027 |
|---|---|---|
| « Ce mois » | **5 000 FCFA** | **0 FCFA** |

`pro_dashboard.png` moves, and it moves *for the reason row 23 named*: `now + 2d`
falls into October, the month bucket empties. The picture is provably a function
of the frozen clock, which no amount of byte-identity could have shown.

**The rule, stated properly:** identity proves absence of leakage only for a
screen that renders nothing clock-derived. For one that does, sensitivity has to
be demonstrated by a freeze that *changes the value*.

**And by that rule `pro_earnings` is not yet proven.** Its default tab is
« Aujourd'hui », and `MockData` seeds at `now ± days` — never on today — so it
renders 0 FCFA and « Aucune transaction » at every instant tried. The picture
pins the screen's tokens (which is what exposed §21 row 40) but says nothing
about whether its buckets follow the clock. That is a limitation of the *fixture*,
not of the seam, and it belongs to the earnings slice row 40 asks for.

## Definition of done

Row 23 → **0** with all three of its errors recorded rather than restated · the
seam in `core/`, called by three roots and **three** test shells · the pin living
with §18's firewall · three goldens, each **proven under two different frozen
dates to be byte-identical** · §20.1 loses its second bullet **and its stale "19
goldens"** (there are 22, soon 25) · the determinism rule promoted from
`timezone-salon-time.md` into ROADMAP Part 4/7, where the DoD can see it ·
ROADMAP (French) · adversarial review.
