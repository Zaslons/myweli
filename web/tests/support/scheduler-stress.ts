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
/// So under this flag: (1) the Scheduler's clock gains SCHEDULER_SKEW_MS on every
/// read, so it yields after EVERY task; (2) every zero-delay `setTimeout` is
/// followed by PREEMPT_MS of busy CPU. A test that reads effect output without
/// waiting for it now fails every time instead of once in a few hundred runs.
///
/// tests/scheduler-stress.test.tsx holds the canary that proves both halves still
/// bite (a React or Scheduler upgrade could make this file inert), and the pins on
/// the npm script and the CI job.

/// More than the Scheduler's 5 ms slice: one read is enough to make it yield.
export const SCHEDULER_SKEW_MS = 6;
/// Comfortably over the ~1 ms at which the drain's timer starts winning.
export const PREEMPT_MS = 2;

const MARK = '__myweliSchedulerStress';

function busyWait(ms: number): void {
  const t0 = process.hrtime.bigint();
  while (Number(process.hrtime.bigint() - t0) / 1e6 < ms) {
    // The CPU is taken: nothing else on this thread runs.
  }
}

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

type AnyTimer = (...args: unknown[]) => unknown;
const g = globalThis as unknown as Record<string, unknown> & { setTimeout: AnyTimer };
if (!g[MARK]) {
  const realSetTimeout = g.setTimeout;
  g.setTimeout = (...args: unknown[]) => {
    const id = realSetTimeout(...args);
    if (!args[1]) busyWait(PREEMPT_MS);
    return id;
  };
  g[MARK] = true;
}
