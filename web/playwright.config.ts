import { defineConfig } from '@playwright/test';

const PORT = 3000;
const STUB_PORT = 8787;
const baseURL = `http://127.0.0.1:${PORT}`;

/// Hermetic e2e: a stub API (no real backend) + the built Next app pointed at it.
/// The app fetches server-side, so the stub URL must be inlined at build time.
/// The WHOLE harness is pinned to UTC — browser (`timezoneId`) + stub + Next
/// processes (`TZ`) — so date-boundary seeds are deterministic on any dev
/// machine (docs/design/timezone-salon-time.md §4; the salon zone is UTC+0).
export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  /// The **assertion** timeout, stated rather than inherited (B10 §4.4).
  /// `timeout` above is the per-test budget; without this block every
  /// `toHaveURL` / `toBeVisible` silently ran on Playwright's 5 s default while
  /// the config appeared to promise 30 s. 5 s is the right value and is kept —
  /// the flakes B10 fixed were deterministic bugs that no timeout would reach.
  expect: { timeout: 5_000 },
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  /// **Zero, deliberately** (B10, docs/design/web-b10-flake.md).
  /// `retries: 1` was converting a measured ~1-in-6 red rate into a ~0–2 % one
  /// by re-running the failed test alone in the quiet tail of the job — which
  /// is precisely the `--workers=1` condition under which the flakes do not
  /// reproduce at all. A green built that way carries no information.
  retries: 0,
  reporter: 'line',
  use: {
    baseURL,
    timezoneId: 'UTC',
    /// **Because `retries: 0` means a red run is the ONLY look you get at it.**
    ///
    /// B10 removed the retry on the argument that a green built by re-running
    /// alone carries no information. That argument holds, and it has a cost the
    /// slice did not pay: with no retry and no artifact, a CI failure leaves
    /// nothing but a stack.
    ///
    /// A14b's PR hit exactly that. `axe.spec.ts` timed out inside a five-route
    /// loop, and because Playwright attributes a test-level timeout to whatever
    /// call is in flight, the stack could not say **which** route was loading —
    /// so "the server was hanging on an image" and "the 30 s budget simply ran
    /// out four routes in" stayed indistinguishable. A trace answers that in one
    /// look, and costs nothing on a green run.
    trace: 'retain-on-failure',
  },
  /// **Neither server is ever reused, locally or on CI** (B10 §4.3).
  ///
  /// The stub holds all of its state in module-level variables and has no
  /// reset, so a surviving process carries one run's bookings, uploads and
  /// profile edits into the next: three consecutive runs against one stub
  /// measured 3 → 14 → 16 failures. That monotonic decay was the "2-in-3" row
  /// 30 recorded, and it only ever happened locally, because CI already got
  /// fresh processes.
  ///
  /// The Next server is worse than stateful — it is a **build artifact**.
  /// Reusing it skips `npm run build`, so a local run silently exercises the
  /// previous build of whatever you just edited and reports green about code
  /// that is not under test. Paying ~60 s per run is the price of a gate that
  /// answers the question it was asked.
  ///
  /// **The footgun, and its remedy.** An occupied port is now a hard error
  /// before any test runs — and `npm run dev` uses this same port 3000, so the
  /// suite will refuse to start while a dev server is up. A hard-killed run can
  /// also orphan one of these. Playwright's own error advises setting
  /// `reuseExistingServer: true`; **do not** — that is the defect, not the fix.
  /// Free the ports instead:
  ///
  ///     lsof -ti:3000 -ti:8787 | xargs kill
  webServer: [
    {
      command: `node tests/e2e/stub-api.mjs`,
      port: STUB_PORT,
      reuseExistingServer: false,
      env: { TZ: 'UTC' },
    },
    {
      command: `npm run build && npm run start`,
      url: baseURL,
      timeout: 180_000,
      reuseExistingServer: false,
      env: {
        NEXT_PUBLIC_API_BASE_URL: `http://127.0.0.1:${STUB_PORT}`,
        NEXT_PUBLIC_SITE_URL: baseURL,
        // **Without this the Google button does not render at all**, and every
        // assertion about it passes for the wrong reason — which is exactly
        // what happened: `legal.spec.ts`'s cookie check looped over an empty
        // array for weeks while the real page set `g_state` on load. A dummy
        // id is enough; the suite never lets a request reach Google (it is
        // intercepted), so the value only has to be non-empty.
        NEXT_PUBLIC_GOOGLE_CLIENT_ID: 'e2e-dummy.apps.googleusercontent.com',
        // Same reasoning as the line above, one control further on: the
        // « Aide & Support » row and the pro « Nous contacter » CTA now render
        // NOTHING when no number is configured, rather than linking to
        // `wa.me/?text=…` — WhatsApp's landing page, which looks like it
        // worked. Without a value here the e2e would assert against a row that
        // is legitimately absent. The absent case is covered by
        // `tests/support.test.ts`; this covers the configured one.
        NEXT_PUBLIC_MYWELI_WHATSAPP: '2250700000000',
        TZ: 'UTC',
      },
    },
  ],
});
