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

/// **The routes worth watching, and an honest note about which of them
/// actually exercise a phone field.** The list held `/`, `/connexion` and
/// `/pro/connexion` and passed — while `/pro/inscription` fetched a flag SVG
/// from `purecatamphetamine.github.io` on load, because
/// `react-phone-number-input` defaults `flagUrl` to a GitHub Pages host. The
/// guard was green on the pages someone had thought of, which is the failure an
/// allowlist is supposed to prevent, not reproduce.
///
/// Widening it exposed a second, quieter problem an audit had to point out:
/// **most of these do not render a phone field at all.** `/mon-compte` redirects
/// to `/connexion?returnTo=…` when anonymous, so that row measures `/connexion`
/// a second time; `/connexion` itself is email-first and renders no phone input
/// until after sign-in. Exactly ONE listed route — `/pro/inscription` —
/// exercises a `PhoneField` anonymously.
///
/// They are all still worth checking for third parties. But the list is not the
/// phone-field coverage it reads as, so the test below pins the premise
/// separately: if the one route that does exercise one ever stops, this file
/// becomes a third-party check that no longer covers the defect it was widened
/// for, and it should say so out loud rather than stay green.
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

/// The premise of the list above: at least one route really does render a phone
/// field, with its flag coming from our own origin. Without this the whole
/// widening degrades into checking pages that were never at risk.
test('a phone field really is exercised, and its flag is ours', async ({ page }) => {
  await page.goto('/pro/inscription');
  await page.waitForLoadState('networkidle');

  const flag = page.locator('img[src*="/flags/"]').first();
  await expect(
    flag,
    'no phone-field flag rendered — the third-party list no longer covers the '
      + 'case it was widened for',
  ).toBeVisible();

  const src = await flag.getAttribute('src');
  expect(src, 'the flag must be same-origin, not a vendor CDN').toMatch(/^\/flags\//);

  // And it must actually load: a 404 from OUR origin is not a foreign host, so
  // the allowlist above is structurally blind to it.
  const res = await page.request.get(new URL(src!, page.url()).toString());
  expect(res.status(), 'the flag 404s — has the prebuild copy run?').toBe(200);
});

/// The same headers, **on production**. A `next.config.mjs` header can be
/// correct in source and absent from the deployment, and nothing else here would
/// notice — the same gap that let a privacy policy contradict its own bundle.
test('production sends the security headers', async ({ request }) => {
  const h = (await request.get('/')).headers();
  expect(h['x-frame-options']).toBe('DENY');
  expect(h['x-content-type-options']).toBe('nosniff');
  expect(h['referrer-policy']).toBe('strict-origin-when-cross-origin');

  // Vercel already sends HSTS; we deliberately do not re-declare it, because
  // re-declaring risks weakening it. Assert it is there all the same — the
  // promise is that the site has it, not that we set it.
  expect(h['strict-transport-security'], 'HSTS disappeared').toBeTruthy();

  const csp = h['content-security-policy-report-only'];
  expect(csp, 'the CSP is absent from the deployment').toBeTruthy();
  expect(csp).toContain('*.r2.cloudflarestorage.com');
  expect(csp).toContain('worker-src blob:');
  // Violations must reach a person, or Report-Only is a policy nobody reads.
  expect(csp, 'no report-uri — violations would go nowhere').toContain('report-uri');
});
