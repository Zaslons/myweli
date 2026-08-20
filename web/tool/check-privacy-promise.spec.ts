import { expect, test } from '@playwright/test';

/// **Does the DEPLOYED site keep the promises the privacy policy makes?**
///
/// Run against a real url, not the e2e build:
///
///   npm run check:privacy                       # production
///   PRIVACY_URL=https://staging… npm run check:privacy
///
/// **Why this cannot live in `tests/e2e/`.** `Sentry.init` does not run
/// client-side in the e2e build — `window.__SENTRY__` holds a scope and no
/// client — so every in-browser assertion about Sentry passes there for the
/// wrong reason. Three versions were watched passing while the telemetry
/// integrations were deliberately re-enabled:
///
///   1. `page.on('request')` — blind: the SDK caches a native `fetch` at init,
///      by design, so tooling instrumentation cannot intercept its transport.
///      The same blindness produced a false "web crash reporting is broken"
///      reading against production earlier the same day.
///   2. Resource Timing with a DSN on a `.invalid` host — DNS fails so early
///      that no entry is ever created.
///   3. Resource Timing with a DSN on the local stub — the DSN is inlined into
///      the bundle, but `Sentry.init` still never runs, so nothing is sent.
///
/// Against a deployed site the SDK is live and Resource Timing sees every
/// request however it was made. That is the only arrangement in which these
/// assertions can fail, which is the only arrangement worth shipping.
///
/// History: the live policy denied using Sentry while the bundle posted to it
/// (2026-08-12), then said « aucun rapport … lorsque rien n'a échoué » while a
/// clean load sent three session envelopes (2026-08-20). Both lived in the
/// served bundle, where a source-level test cannot look.

const target = process.env.PRIVACY_URL ?? 'https://myweli.com';

test.use({ baseURL: target });

test('a clean page load sends NOTHING to Sentry', async ({ page }) => {
  await page.goto('/');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(2000);
  const sent = await page.evaluate(() =>
    performance
      .getEntriesByType('resource')
      .map((e) => e.name)
      .filter((n) => /\/envelope\//.test(n)),
  );
  expect(
    sent,
    '« Nous n’envoyons aucun rapport à Sentry lorsque rien n’a échoué » — '
      + 'a session, a transaction or a client report is still a report',
  ).toEqual([]);
});

test('the SDK is actually live, so the check above can fail', async ({ page }) => {
  // The control. Without it, a deployment that simply dropped the DSN would
  // make the assertion above pass while proving nothing at all.
  await page.goto('/');
  const live = await page.evaluate(() => {
    const c = (window as unknown as { __SENTRY__?: Record<string, unknown> }).__SENTRY__;
    return !!c;
  });
  expect(live, 'Sentry is not initialised on the deployed site — the promise check is vacuous').toBe(true);
});

test('a public page sets no cookie', async ({ page, context }) => {
  await context.clearCookies();
  await page.goto('/mentions-legales');
  await page.waitForLoadState('networkidle');
  expect((await context.cookies()).map((c) => c.name)).toEqual([]);
});
