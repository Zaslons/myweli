/// The stub's time seam — the one place in the harness allowed to ask what day
/// it is.
///
/// ## The bug this exists to prevent
///
/// `stub-api.mjs` used to compute its "today" ONCE, at module load:
///
///     const todayAt9 = `${new Date().toISOString().slice(0, 10)}T09:00:00.000Z`;
///
/// The comment above it promised the pro views would show that booking
/// "whenever the suite runs". They do not. The stub is a long-lived process
/// started by Playwright's `webServer`, and the Next build that follows it can
/// take three minutes — while the APP derives its own "today" per render, from
/// `salonDayKey()` in `lib/time.ts`. Boot the stub at 23:58 and assert at
/// 00:01 and the two disagree: the seeded booking is dated yesterday, the pro
/// « Aujourd'hui » view filters for today, and the row is simply absent.
///
/// Measured 2026-08-19: CI run 32199379368 spanned midnight and failed 5 of
/// 168 — every one a date-dependent pro spec. Run 32200382938, on a tree
/// differing by one merged PR but starting after midnight, passed all of them.
/// The suite is green at every hour except one, which is the worst shape a
/// flake can have: it fails a future PR at random and looks like that PR's
/// fault.
///
/// ## The fix
///
/// Dates in the fixtures are written as TOKENS and materialised in `json()`, at
/// the instant the response is serialised. The stub therefore answers with the
/// day it is when it is ASKED, which is the same question the app asks
/// milliseconds later.
///
/// Residual, stated rather than papered over: a response serialised at
/// 23:59:59.999 and rendered at 00:00:00.001 still disagrees. That window is
/// sub-second and cannot be closed from this side — the app's clock is the
/// app's own, deliberately, because that is the production behaviour under
/// test. What it replaces is a window of minutes to hours.

/// Substituted for the current salon day at response time.
export const TODAY = '@TODAY@';

/// Substituted for the day after. Consumer bookings sit here so future-only
/// actions (« Reporter ») remain reachable.
export const TOMORROW = '@TOMORROW@';

/// The salon day key, at the moment it is asked for.
///
/// `Africa/Abidjan` is UTC+0 with no DST, so the salon day and the UTC day
/// coincide — this deliberately mirrors `SALON_TZ` in `lib/time.ts`, which is
/// what the app filters on. If the launch market ever moves off UTC, this and
/// `lib/time.ts` have to move together, and the test in `tests/stub-clock.test.ts`
/// is what will notice: it uses the app's own `salonDayKey` as its oracle
/// rather than restating the rule.
export function stubDayKey(now = new Date(), offsetDays = 0) {
  return new Date(now.getTime() + offsetDays * 86_400_000)
    .toISOString()
    .slice(0, 10);
}

/// Replace every token in a string — a whole serialised payload, or a single
/// fixture field about to be COMPARED.
///
/// The second case is not hypothetical and was not caught by any unit test: the
/// `/earnings` handler filters its ledger with `t.date >= start`, a plain
/// string comparison against the ISO range the app sends. A token there is not
/// a date, the comparison is nonsense, and the « Aujourd'hui » total silently
/// came out empty. A fixture value is only safe to leave tokenised while the
/// only thing that ever happens to it is being written out.
export function materialiseDates(serialised, now = new Date()) {
  return serialised
    .replaceAll(TODAY, stubDayKey(now))
    .replaceAll(TOMORROW, stubDayKey(now, 1));
}
