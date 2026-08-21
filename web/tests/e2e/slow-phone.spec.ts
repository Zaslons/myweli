import { expect, test } from '@playwright/test';

/// **The funnel on a slow phone — the checklist item, made repeatable.**
///
/// LAUNCH.md §6.1 asks for "the full funnel on a real phone browser on a slow
/// connection". Done once by hand, that answer is true for a day. This runs it
/// every CI.
///
/// **Nothing else in the suite throttles anything.** The other spec files drive
/// an unthrottled desktop Chromium on localhost, where 232 KB of JS costs
/// nothing and every page is instant. That is why the 404 empty shell — a blank
/// white page until the JS landed — was green in four different files for weeks.
///
/// **What this cannot tell you.** It runs against the stub on loopback, so the
/// numbers are not production numbers: no CDN, no TLS handshake to Abidjan, no
/// real API latency. It measures the SHAPE of the funnel under constraint.
/// Real-domain numbers are a separate, scheduled job (`production-checks.yml`).
///
/// ---
///
/// **Three of its four steps could not fail, and that is the point of the
/// rewrite (2026-08-21).** The original matched loose alternations against
/// `body`, which includes the site chrome:
///
///   `/`            `/Réservez|salon/i` — the STATIC hero (`page.tsx:90`) and
///                  the install banner both match; the API-backed section is
///                  `featured.length > 0 ? … : null`, so an empty catalogue
///                  passed just as well
///   `/recherche`   `/tresses|…/i`      — matched the ECHOED QUERY STRING
///                  (`recherche/page.tsx:52` renders « Recherche : tresses »)
///   `/reserver`    `/service|réserv/i` — matched **the site footer**
///                  (`SiteFooter.tsx:28`, "réservation"), present on every page
///                  including a blank error page
///
/// Each now asserts something **only the working page can produce**, scoped to
/// `#contenu` so the chrome cannot satisfy it.
const SLOW_3G = {
  offline: false,
  // ~1.6 Mbps down / 750 kbps up, 150 ms RTT — Chrome DevTools' "Slow 3G" is
  // harsher than most Abidjan connections; this is "Fast 3G", the mid-range
  // case docs/WEB.md §7 budgets against.
  downloadThroughput: (1.6 * 1024 * 1024) / 8,
  uploadThroughput: (750 * 1024) / 8,
  latency: 150,
};

/// A named budget, and it has to sit **strictly below** the test timeout or it
/// can never be the thing that fails.
///
/// The original asserted `elapsed < 30_000` while `playwright.config.ts` sets
/// `timeout: 30_000` and the content wait also used 30_000 — so a slow step
/// died on the timeout at line one and `Date.now()` never ran. The assertion
/// was unreachable code wearing a budget's clothes.
const BUDGET_MS = 20_000;
const CONTENT_TIMEOUT_MS = 30_000;

/// Values that exist ONLY in the stub's data (`tests/e2e/stub-api.mjs`), never
/// in the layout, the footer, the install banner or an echoed query.
const STEPS: [path: string, mustSee: RegExp, why: string][] = [
  ['/', /Beauté Divine/i, 'the featured salon, i.e. the API answered'],
  [
    '/recherche?q=tresses',
    /Beauté Divine/i,
    'a real result card, not the echoed query',
  ],
  ['/beaute-divine', /Salon de coiffure à Cocody/i, 'the salon’s own description'],
  [
    '/beaute-divine/reserver',
    /Soin visage/i,
    'a service from the catalogue, not the footer’s « réservation »',
  ],
  [
    '/this-does-not-exist',
    /Page introuvable/i,
    'the 404 the box actually names — blank until 2026-08-21',
  ],
];

test.describe('the funnel under 3G and a 4x-slower CPU', () => {
  test.setTimeout(90_000);

  async function throttle(page: import('@playwright/test').Page) {
    // Page-level, not browser-level: `newBrowserCDPSession()` cannot emulate
    // network conditions for a page, and the tests using it failed while the
    // one using this passed.
    const session = await page.context().newCDPSession(page);
    await session.send('Network.enable');
    await session.send('Network.emulateNetworkConditions', SLOW_3G);
    await session.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  }

  for (const [path, mustSee, why] of STEPS) {
    test(`${path} renders ${why}`, async ({ page }) => {
      await throttle(page);
      const started = Date.now();
      await page.goto(path, { waitUntil: 'domcontentloaded' });
      // `#contenu` is the layout's content div — everything the chrome renders
      // (header, install banner, footer) is OUTSIDE it.
      await expect(page.locator('#contenu')).toContainText(mustSee, {
        timeout: CONTENT_TIMEOUT_MS,
      });
      const elapsed = Date.now() - started;
      expect(
        elapsed,
        `${path} took ${elapsed}ms to show anything useful`,
      ).toBeLessThan(BUDGET_MS);
    });
  }

  /// **The property the whole item is about: something useful arrives BEFORE
  /// the JS does.** Every assertion above runs a JS-enabled browser, so all of
  /// them would still pass on a page that renders nothing server-side and
  /// hydrates into shape — which is exactly what the 404 did for weeks.
  test('the same pages are useful with no JavaScript at all', async ({
    request,
  }) => {
    const visibleText = (html: string) =>
      html
        .replace(/<script[\s\S]*?<\/script>/g, '')
        .replace(/<style[\s\S]*?<\/style>/g, '')
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();

    for (const [path, mustSee, why] of STEPS) {
      const text = visibleText(await (await request.get(path)).text());
      expect(text, `${path} — ${why} — is not in the served HTML`).toMatch(
        mustSee,
      );
    }
  });

  test('the whole path is walkable end to end while throttled', async ({
    page,
  }) => {
    await throttle(page);
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await page.goto('/beaute-divine', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('h1')).toContainText(/Beauté Divine/i, {
      timeout: CONTENT_TIMEOUT_MS,
    });
    await page.goto('/beaute-divine/reserver', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#contenu')).toContainText(/Soin visage/i, {
      timeout: CONTENT_TIMEOUT_MS,
    });
  });
});
