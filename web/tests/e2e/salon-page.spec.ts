import { expect, test, type Locator, type Page } from '@playwright/test';

import { routeNextImages } from './_pixel';
import before from './salon-seo-before.json';

/// The salon page with its cover in 3:2 (docs/design/web-swiss-salon.md §1.4, §1.8, §1.10):
/// what a computer sees on its first screen, the booking panel that stays in view, the
/// phone's booking bar against the footer and the heart's message, the focus that no longer
/// jumps, and what search engines read. The cover's own shape and place are
/// site-look.spec.ts's, beside the rest of the site's left edge.
///
/// **What this cannot see:** whether it looks right, and any browser but Chromium (§1.14).

const SALON = '/beaute-divine';

const size = (page: Page, width: number, height: number) => page.setViewportSize({ width, height });

/// Whether a press at a point of `el` lands on it: the browser's own answer, which counts
/// whatever stands over it, a sticky bar or a toast included.
const answersAt = (el: Locator, at: 'centre' | 'top-left') =>
  el.evaluate((node, where) => {
    const r = node.getBoundingClientRect();
    const [x, y] = where === 'centre' ? [r.x + r.width / 2, r.y + r.height / 2] : [r.x + 1, r.y + 1];
    const hit = document.elementFromPoint(x, y);
    return !!hit && (hit === node || node.contains(hit));
  }, at);

const scrollTo = (heading: Locator, block: 'start' | 'center') =>
  heading.evaluate((el, b) => el.scrollIntoView({ block: b, behavior: 'instant' }), block);

/// The map's controls a keyboard reaches (MapLibre's own names), mounted before the Tab walk.
const MAP_CONTROLS = ['Zoom in', 'Zoom out', 'Toggle attribution', 'MapLibre'];

/// The panel's « Réserver », in columns 9–12 from `lg`.
const panelCta = (page: Page) => page.locator('main aside').getByRole('link', { name: 'Réserver', exact: true });
/// The phone's booking bar: the last thing in `main` (salon-page.test.tsx holds the order).
const bar = (page: Page) => page.locator('main > :last-child');

test.describe('a computer: the name and « Réserver » beside the photo (§1.2)', () => {
  for (const [width, height] of [
    [1024, 768],
    [1280, 800],
    [1366, 768],
  ] as const) {
    test(`at ${width}×${height} the <h1>, the rating and « Réserver » are on the first screen`, async ({ page }) => {
      await size(page, width, height);
      await routeNextImages(page);
      await page.goto(SALON);
      const name = page.locator('main header');
      for (const [what, element] of [
        ['the <h1>', page.getByRole('heading', { level: 1 })],
        ['the rating', name.locator('p').filter({ hasText: '(2 avis)' })],
        ['« Réserver »', panelCta(page)],
      ] as const) {
        const b = await element.boundingBox();
        expect(b, `${what} has no box`).not.toBeNull();
        expect(b!.y, `${what} is above the screen`).toBeGreaterThanOrEqual(0);
        expect(b!.y + b!.height, `${what} is below the first screen`).toBeLessThanOrEqual(height);
        expect(b!.x + b!.width, `${what} is off the screen’s side`).toBeLessThanOrEqual(width);
      }
      expect(await page.evaluate(() => window.scrollY), 'the page moved by itself').toBe(0);
    });
  }

  // Only the panel sticks, at `top-l`. At the very end of the page it rides up with its
  // column, and nothing is asserted there (§1.4).
  for (const [width, height] of [
    [1280, 800],
    [1024, 768],
  ] as const) {
    for (const [label, heading] of [
      ['Avis', /^Avis \(/],
      ['Questions fréquentes', /^Questions fréquentes$/],
    ] as const) {
      test(`at ${width}×${height}, read down to « ${label} », the panel stays in view and answers`, async ({ page }) => {
        await size(page, width, height);
        await routeNextImages(page);
        await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
        await page.goto(SALON);
        await scrollTo(page.getByRole('heading', { name: heading }), 'start');
        const scrolled = await page.evaluate(() => window.scrollY);
        // The panel starts 157px down and is 226 tall: past 400 one that did not stick is gone.
        expect(scrolled, 'not read far enough, so this proves nothing').toBeGreaterThan(400);
        const panel = (await page.locator('main aside').boundingBox())!;
        expect(Math.abs(panel.y - 24), `the panel’s top is at ${panel.y}`).toBeLessThanOrEqual(1);
        expect(await answersAt(panelCta(page), 'centre')).toBe(true);
      });
    }
  }
});

// The sections' column is 984px wide at 1920 (columns 1–8 of the site's container), and a
// review's text ran its whole width, past direction §6.1's 720px reading cap, which the intro
// and the FAQ already keep (§1.1 item 4).
test('at 1920×1080 a review’s text keeps its reading width (§1.1)', async ({ page }) => {
  await size(page, 1920, 1080);
  await routeNextImages(page);
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
  await page.goto(SALON);
  const text = page.locator('main p').filter({ hasText: /^Service impeccable\.$/ });
  const card = (await text.locator('xpath=ancestor::li[1]').boundingBox())!;
  expect(card.width, 'the review’s card is no wider than the cap, so this proves nothing').toBeGreaterThan(760);
  const p = (await text.boundingBox())!;
  expect(p.width, `the review runs ${p.width}px wide`).toBeLessThanOrEqual(720);
});

test.describe('the page does not jump to the heart on load (§1.4)', () => {
  // On `main` and #737 the heart took the focus on load: 317px down at 320×568 and 454px at
  // 844×390, past the cover. At 1280 the heart is on the first screen, so only the focus
  // can say it there.
  for (const [width, height] of [
    [320, 568],
    [844, 390],
    [1280, 800],
  ] as const) {
    test(`at ${width}×${height} it opens at the top, with the focus on nothing`, async ({ page }) => {
      await size(page, width, height);
      await routeNextImages(page);
      const favourites = page.waitForResponse((r) => r.url().includes('/api/me/favorites'));
      await page.goto(SALON);
      // The heart's read goes out from the same commit as its focus effect, so once it is
      // answered the effect has run.
      await favourites;
      await expect(page.getByRole('button', { name: 'Ajouter aux favoris' })).toBeEnabled();
      expect(await page.evaluate(() => window.scrollY)).toBe(0);
      expect(await page.evaluate(() => document.activeElement === document.body)).toBe(true);
    });
  }
});

test.describe('a phone: the booking bar (§1.4)', () => {
  const PHONES = [
    [390, 844],
    [320, 568],
  ] as const;

  for (const [width, height] of PHONES) {
    // Fixed, the 65px bar stood on « Instagram » at the page's end, and a press there
    // landed on the bar. Sticky, it stops above the footer, as « Carte » does.
    test(`at ${width}×${height}, at the page’s end, every footer link answers and the bar is above the footer`, async ({ page }) => {
      await size(page, width, height);
      await routeNextImages(page);
      await page.goto(SALON);
      await page.evaluate(() =>
        window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' }),
      );
      const b = (await bar(page).boundingBox())!;
      const footer = (await page.locator('footer').boundingBox())!;
      expect(b.y + b.height, 'the bar reaches the footer').toBeLessThanOrEqual(footer.y);
      // Last link first, each brought on-screen only if it is not, as site-look's « Carte »
      // test does: `elementFromPoint` answers nothing off the screen.
      const links = await page.locator('footer a').evaluateAll((els) =>
        els.reverse().map((el) => {
          el.scrollIntoView({ block: 'nearest', behavior: 'instant' });
          const r = el.getBoundingClientRect();
          const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
          return { name: el.textContent?.trim(), answers: !!hit && (hit === el || el.contains(hit)) };
        }),
      );
      expect(links.map((l) => l.name), 'the link it used to stand on').toContain('Instagram');
      expect(links.filter((l) => !l.answers)).toEqual([]);
    });

    test(`at ${width}×${height}, mid-page, the bar stands at the screen’s foot and « Réserver » answers`, async ({ page }) => {
      await size(page, width, height);
      await routeNextImages(page);
      await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
      await page.goto(SALON);
      await scrollTo(page.getByRole('heading', { name: /^Avis \(/ }), 'center');
      expect(await page.evaluate(() => window.scrollY), 'not scrolled, so this proves nothing').toBeGreaterThan(height);
      const b = (await bar(page).boundingBox())!;
      expect(Math.abs(b.y + b.height - height), `the bar’s foot is at ${b.y + b.height}`).toBeLessThanOrEqual(0.5);
      expect(await answersAt(bar(page).getByRole('link', { name: 'Réserver', exact: true }), 'centre')).toBe(true);
    });

    // The heart's « Ajouté aux favoris » stood on the bar: at 320 « Annuler » took a corner of
    // « Réserver », and a press there undid the favourite. Lifted, it ends above the bar.
    test(`at ${width}×${height}, the heart’s message stands above the bar, and « Réserver » takes its corner`, async ({ page }) => {
      await size(page, width, height);
      await routeNextImages(page);
      await page.route('**/api/me/favorites**', (r) =>
        r.request().method() === 'GET'
          ? r.fulfill({ status: 200, contentType: 'application/json', body: '{"favorites":[]}' })
          : r.fulfill({ status: 204 }),
      );
      await page.goto(SALON);
      const heart = page.getByRole('button', { name: 'Ajouter aux favoris' });
      await expect(heart).toBeEnabled();
      await heart.evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
      await heart.click();
      const pill = page.getByRole('status').filter({ hasText: 'Ajouté aux favoris' }).locator('div').first();
      await expect(pill).toBeVisible();
      await expect(pill.getByRole('button', { name: 'Annuler' })).toBeVisible();
      const toast = (await pill.boundingBox())!;
      const b = (await bar(page).boundingBox())!;
      expect(b.y + b.height, 'the bar is not at the screen’s foot, so this proves nothing').toBeCloseTo(height, 0);
      expect(toast.y + toast.height, 'the message reaches the bar').toBeLessThanOrEqual(b.y);
      expect(await answersAt(bar(page).getByRole('link', { name: 'Réserver', exact: true }), 'top-left')).toBe(true);
    });
  }

  // With the browser's text at double size (Chrome's font-size setting, a 32px root), the bar
  // is 113px: `min-h-12` is rem. The px lift ended the pill 33px down into it, and at 320 and
  // 360 « Annuler » took a corner of « Réserver », so a press there undid the favourite
  // (measured by the review of this branch). The lift is rem now, like the bar.
  for (const [width, height] of [
    [320, 568],
    [360, 640],
  ] as const) {
    test(`at ${width}×${height} with the browser’s text at double size, the heart’s message stands above the bar`, async ({ page }) => {
      await size(page, width, height);
      const cdp = await page.context().newCDPSession(page);
      await cdp.send('Page.setFontSizes', { fontSizes: { standard: 32, fixed: 26 } });
      await routeNextImages(page);
      await page.route('**/api/me/favorites**', (r) =>
        r.request().method() === 'GET'
          ? r.fulfill({ status: 200, contentType: 'application/json', body: '{"favorites":[]}' })
          : r.fulfill({ status: 204 }),
      );
      await page.goto(SALON);
      expect(
        await page.evaluate(() => getComputedStyle(document.documentElement).fontSize),
        'the text is not doubled, so this proves nothing',
      ).toBe('32px');
      const heart = page.getByRole('button', { name: 'Ajouter aux favoris' });
      await expect(heart).toBeEnabled();
      await heart.evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
      await heart.click();
      const pill = page.getByRole('status').filter({ hasText: 'Ajouté aux favoris' }).locator('div').first();
      await expect(pill).toBeVisible();
      await expect(pill.getByRole('button', { name: 'Annuler' })).toBeVisible();
      const toast = (await pill.boundingBox())!;
      const b = (await bar(page).boundingBox())!;
      expect(b.height, 'the bar did not grow with the text, so this proves nothing').toBeGreaterThan(100);
      expect(b.y + b.height, 'the bar is not at the screen’s foot, so this proves nothing').toBeCloseTo(height, 0);
      expect(toast.y + toast.height, 'the message reaches the bar').toBeLessThanOrEqual(b.y);
      expect(await answersAt(bar(page).getByRole('link', { name: 'Réserver', exact: true }), 'top-left')).toBe(true);
    });
  }

  // The browser scrolls a focused control just into view at the screen's foot, under the
  // bar: the FAQ's « Quels sont les tarifs… » was hidden whole at 390 and 1023, and all but
  // 0.3px of « Comment réserver… » at 320 (measured on this page before its fix, §1.4). Each
  // column keeps 96px clear below `lg`.
  // At a doubled browser font 17px can still sit under the 113px bar, and that is recorded
  // in §1.4, not held here.
  for (const [width, height] of [...PHONES, [1023, 768]] as const) {
    test(`at ${width}×${height}, nothing the keyboard reaches stands under the bar`, async ({ page }) => {
      await size(page, width, height);
      await routeNextImages(page);
      await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
      await page.goto(SALON);
      await expect(page.getByRole('button', { name: 'Ajouter aux favoris' })).toBeEnabled();
      // The map mounts only once it nears the screen (MapEmbed's IntersectionObserver, then a
      // dynamic import), which a walk from the top passed before it existed: its controls were
      // never focused, and in planning two of them stood whole under the bar. So it is mounted
      // first. Mounting it moves where Chromium's Tab key starts, so the start is put back at
      // the top of the document: a focus on a sentinel there, which then goes.
      const map = page.getByRole('region', { name: /^Carte — / });
      await map.evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
      await expect(map.getByRole('button', { name: 'Zoom in' })).toBeAttached({ timeout: 15_000 });
      await page.evaluate(() => {
        window.scrollTo({ top: 0, behavior: 'instant' });
        const start = document.createElement('span');
        start.tabIndex = -1;
        document.body.prepend(start);
        start.focus();
        start.remove();
      });
      const under: string[] = [];
      const seen: string[] = [];
      for (let i = 0; i < 120; i++) {
        await page.keyboard.press('Tab');
        const stop = await page.evaluate(() => {
          const el = document.activeElement as HTMLElement | null;
          if (!el || el === document.body || el.closest('footer')) return null;
          const bar = document.querySelector('main > :last-child')!;
          const name = (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 48);
          if (bar.contains(el)) return { name, under: 0, inBar: true };
          const b = el.getBoundingClientRect();
          const t = bar.getBoundingClientRect();
          return { name, under: Math.max(0, Math.min(b.bottom, t.bottom) - Math.max(b.top, t.top)), inBar: false };
        });
        if (stop === null) break;
        seen.push(stop.name);
        if (!stop.inBar && stop.under > 0) under.push(`« ${stop.name} »: ${stop.under}px under the bar`);
      }
      // The walk has to start at the top and reach the map's controls and the FAQ's last
      // question, or it proved nothing about what it skipped.
      expect(seen[0], 'the walk did not start at the top').toBe('Aller au contenu');
      expect(seen, 'the walk never reached the FAQ').toContain('Faut-il payer un acompte ?');
      expect(seen, 'the walk never reached the map').toEqual(expect.arrayContaining(MAP_CONTROLS));
      expect(under).toEqual([]);
    });
  }
});

/// Read from #737's tip, 57b252a8, whose `web/` is b0995489's, built against this stub on
/// 2026-11-06 before any edit to the page (web-swiss-direction.md §12, the salon page's row).
/// The layout moved; the words search engines read did not, and the stub's public salon is
/// never written to, so the list holds in a full run. `meta` and `links` are every `<meta>`
/// (Open Graph's and Twitter's included) and every canonical or alternate link, each with all
/// its attributes, read from the same build the same way when the review asked for them.
test('what search engines read on a salon page has not moved (§1.8)', async ({ page }) => {
  await page.goto(SALON);
  const read = await page.evaluate(() => ({
    h1: document.querySelector('h1')!.textContent,
    title: document.title,
    canonical: document.querySelector('link[rel=canonical]')!.getAttribute('href'),
    description: document.querySelector('meta[name=description]')!.getAttribute('content'),
    ogImage: document.querySelector('meta[property="og:image"]')?.getAttribute('content') ?? null,
    jsonLd: [...document.querySelectorAll('script[type="application/ld+json"]')].map((s) =>
      JSON.parse(s.textContent as string),
    ),
    h2: [...document.querySelectorAll('h2')].map((h) => h.textContent),
    meta: [...document.querySelectorAll('meta')]
      .map((m) => [...m.attributes].map((a) => `${a.name}=${a.value}`).sort().join(' '))
      .sort(),
    links: [...document.querySelectorAll('link[rel=canonical], link[rel=alternate]')]
      .map((l) => [...l.attributes].map((a) => `${a.name}=${a.value}`).sort().join(' '))
      .sort(),
  }));
  expect(read).toEqual(before);
  expect(await page.locator('h1').count(), 'one <h1>').toBe(1);
});
