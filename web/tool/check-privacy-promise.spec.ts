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

/// **The sign-in page, cold, on the real domain — the check that was missing.**
///
/// Nothing here ever visited a sign-in page, so the one place the site DOES
/// talk to a third party was measured nowhere. On 2026-08-21 a manual probe
/// found what that cost: `/connexion` fetched `accounts.google.com/gsi/client`
/// from a mount-time effect and Google set `g_state`, with zero interaction —
/// while the live policy said everything on the page was « strictement
/// nécessaire » and the e2e cookie check looped over an empty array because
/// `NEXT_PUBLIC_GOOGLE_CLIENT_ID` was unset in that build.
///
/// An allowlist rather than a Google-shaped filter: the failure was a host
/// nobody had thought about, so the guard has to fail on hosts nobody has
/// thought about. `fonts.gstatic.com` is on the list because Google Fonts is
/// self-hosted by Next but the FONT FILES are not — that too is a disclosure
/// and belongs in « Qui d'autre les reçoit » before it belongs here.
const ALLOWED_HOSTS = [/(^|\.)myweli\.com$/];

/// **Every route that renders a phone field belongs here, and that was learned
/// the hard way.** This list held `/`, `/connexion` and `/pro/connexion` and
/// passed — while `/pro/inscription` fetched a flag SVG from
/// `purecatamphetamine.github.io` on load, because `react-phone-number-input`
/// defaults `flagUrl` to a GitHub Pages host. The guard was green on the pages
/// someone had thought of, which is the failure mode an allowlist is supposed
/// to prevent, not reproduce.
for (const path of [
  '/',
  '/connexion',
  '/pro/connexion',
  '/pro/inscription',
  '/mon-compte',
]) {
  test(`${path} reaches no third party before any interaction`, async ({
    page,
    context,
  }) => {
    await context.clearCookies();
    await page.goto(path);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    const hosts: string[] = await page.evaluate(() =>
      Array.from(
        new Set(
          performance
            .getEntriesByType('resource')
            .map((e) => {
              try {
                return new URL(e.name).hostname;
              } catch {
                return '';
              }
            })
            .filter(Boolean),
        ),
      ),
    );
    const foreign = hosts.filter(
      (h) => !ALLOWED_HOSTS.some((re) => re.test(h)),
    );
    expect(
      foreign,
      `${path} contacted a third party with no user action — every host here `
        + 'must be named in « Qui d’autre les reçoit », or removed',
    ).toEqual([]);

    expect(
      (await context.cookies()).map((c) => c.name),
      `${path} set a cookie before the visitor chose anything`,
    ).toEqual([]);
  });
}
