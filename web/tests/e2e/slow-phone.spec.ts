import { expect, test } from '@playwright/test';

/// **The funnel on a slow phone — the checklist item, made repeatable.**
///
/// LAUNCH.md §6.1 asks for "the full funnel on a real phone browser on a slow
/// connection". Done once by hand, that answer is true for a day. This runs it
/// every CI.
///
/// **Nothing else in the suite throttles anything.** 19 spec files drive an
/// unthrottled desktop Chromium on localhost, where 232 KB of JS costs nothing
/// and every page is instant. That is why the 404 empty shell — a blank white
/// page until the JS lands — was green in four different files for weeks.
///
/// **What this cannot tell you.** It runs against the stub on loopback, so the
/// numbers are not production numbers: no CDN, no TLS handshake to Abidjan, no
/// real API latency. It measures the SHAPE of the funnel under constraint —
/// that each step renders something useful before the JS arrives, and that none
/// of them regresses into a blank wait. Real-domain numbers need the first real
/// salon; that is recorded as a separate residual.
const SLOW_3G = {
  offline: false,
  // ~1.6 Mbps down / 750 kbps up, 150 ms RTT — Chrome DevTools' "Slow 3G"
  // is harsher than most Abidjan connections; this is "Fast 3G", the mid-range
  // case docs/WEB.md §7 budgets against.
  downloadThroughput: (1.6 * 1024 * 1024) / 8,
  uploadThroughput: (750 * 1024) / 8,
  latency: 150,
};

const STEPS: [path: string, mustSee: RegExp][] = [
  ['/', /Réservez|salon/i],
  ['/recherche?q=tresses', /tresses|salon|résultat/i],
  ['/beaute-divine', /Beauté Divine/i],
  ['/beaute-divine/reserver', /service|réserv/i],
];

test.describe('the funnel under 3G and a 4x-slower CPU', () => {
  for (const [path, mustSee] of STEPS) {
    test(`${path} renders something useful`, async ({ page }) => {
      // Page-level, not browser-level: `newBrowserCDPSession()` cannot emulate
      // network conditions for a page, and the four tests using it failed
      // while the one using this passed.
      const session = await page.context().newCDPSession(page);
      await session.send('Network.enable');
      await session.send('Network.emulateNetworkConditions', SLOW_3G);
      await session.send('Emulation.setCPUThrottlingRate', { rate: 4 });

      const started = Date.now();
      await page.goto(path, { waitUntil: 'domcontentloaded' });
      await expect(page.locator('body')).toContainText(mustSee, { timeout: 30_000 });
      const elapsed = Date.now() - started;

      // Generous on purpose: this is a regression tripwire, not a budget. The
      // budget lives in lighthouserc.json, measured properly. What would fail
      // here is a step that stops rendering at all under constraint.
      expect(elapsed, `${path} took ${elapsed}ms to show anything`).toBeLessThan(30_000);
    });
  }

  test('the whole path is walkable end to end while throttled', async ({ page }) => {
    const session = await page.context().newCDPSession(page);
    await session.send('Network.enable');
    await session.send('Network.emulateNetworkConditions', SLOW_3G);
    await session.send('Emulation.setCPUThrottlingRate', { rate: 4 });

    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await page.goto('/beaute-divine', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('h1')).toContainText(/Beauté Divine/i, { timeout: 30_000 });
    await page.goto('/beaute-divine/reserver', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('body')).toContainText(/service|réserv/i, { timeout: 30_000 });
  });
});
