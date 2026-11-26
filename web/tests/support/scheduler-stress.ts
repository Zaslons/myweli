import { createRequire } from 'node:module';

/// SCHEDULER STRESS — `npm run test:stress` (MYWELI_SCHEDULER_STRESS=1), and the
/// « Web — Unit tests under scheduler stress » CI job. Loaded by vitest.config.ts
/// only under that flag; a plain `npm test` never sees it.
///
/// **What it reproduces, every run, that a loaded CI runner produces only now and
/// then.** A render that runs OUTSIDE act — a fetch resolving while a `findBy…`
/// waits — goes through React's real Scheduler. Two things together then let a
/// test read the page before an effect has run:
///   1. that render takes ≥ 5 ms (the Scheduler's slice, `frameYieldMs`), so it
///      yields before the task that flushes passive effects (`useEffect`);
///   2. the process then loses the CPU for ≥ ~1 ms, so Testing Library's
///      `setTimeout(resolve, 0)` drain fires before the Scheduler's next task,
///      and the test resumes with the effect still pending.
/// Run 45636330662 (2026-11-25) lost « Heures affichées : heure du salon » that
/// way: `SalonTimeHint` draws one effect after the page, and the test read it
/// with a synchronous `getByText`. Measured locally: render +4 ms and a 2 ms stall
/// → 0/15 found; either alone → 14–15/15; the same with the Scheduler unable to
/// yield → 15/15.
///
/// So under this flag the Scheduler's clock gains SCHEDULER_SKEW_MS on every
/// read: it yields after EVERY task, and what an effect draws then needs two more
/// event-loop turns (flush the effect, render its update) — the drain's 1 ms timer
/// wins. Measured: the canary's race 150/150 with the skew alone, 0/50 without.
/// (A 2 ms CPU stall after each zero-delay timer was tried on top and dropped: it
/// changed nothing measurable, so no guard could have said whether it still
/// worked.) A test that reads effect output without waiting for it now fails
/// every run instead of once in a few hundred.
///
/// tests/scheduler-stress.test.tsx holds the canary that proves the skew still
/// bites (a React or Scheduler upgrade could make this file inert), and the pins
/// on the npm script and the CI job.

/// More than the Scheduler's 5 ms slice: one read is enough to make it yield.
export const SCHEDULER_SKEW_MS = 6;

const MARK = '__myweliSchedulerStress';

// The SAME module instance react-dom required: both resolve to
// web/node_modules/scheduler and share Node's require cache. Its development
// build reads the clock through `exports.unstable_now()` at every slice decision,
// so replacing the export is what the Scheduler sees.
const requireCjs = createRequire(import.meta.url);
const scheduler = requireCjs('scheduler') as Record<string, unknown> & {
  unstable_now: () => number;
};

if (!scheduler[MARK]) {
  if (typeof scheduler.unstable_now !== 'function') {
    throw new Error('scheduler-stress: `scheduler.unstable_now` is gone — this setup cannot bite');
  }
  const realNow = scheduler.unstable_now;
  let skew = 0;
  scheduler.unstable_now = () => realNow() + (skew += SCHEDULER_SKEW_MS);
  scheduler[MARK] = true;
}

// Read by tests/scheduler-stress.test.tsx: the flag and this setup travel together.
(globalThis as Record<string, unknown>)[MARK] = true;
