import { expect, test, type Locator, type Page } from '@playwright/test';

import { DOUBLED, answerFavourites, hermetic, rootAt32, scanMessage } from './_message';
import { routeNextImages } from './_pixel';
import before from './salon-seo-before.json';

/// The salon page with its cover in 3:2 (docs/design/web-swiss-salon.md §1.4, §1.8, §1.10):
/// what a computer sees on its first screen, the booking panel that stays in view, the
/// phone's booking bar, which never leaves the screen and keeps the footer clear (decision 103,
/// §3), and the heart's message, the focus that no longer jumps, and what search engines read. The cover's own shape and place are
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

type Text = 'normal' | 'doubled' | 'root32';
const TEXT: Record<Text, string> = {
  normal: 'at normal text',
  doubled: 'with doubled text (Android)',
  root32: 'with a 32px root (a computer’s font at 200 %)',
};
/// Chrome's text scaling on Android needs a touch phone (site-look.spec.ts's recipe), so the
/// doubled cases sit in a `describe` of their own.
const ANDROID = { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } as const;

/// The salon page at a size and a text setting, nothing leaving the machine (the map's tiles
/// included) and the heart answered without a sign-in (_message.ts). Doubled text is put
/// on once the page is up, as Android applies it, so the bar grows under `BarClearance`'s eyes.
async function openAt(page: Page, width: number, height: number, text: Text): Promise<void> {
  await hermetic(page);
  await size(page, width, height);
  await routeNextImages(page);
  await answerFavourites(page);
  if (text === 'root32') await rootAt32(page);
  await page.goto(SALON);
  await expect(page.getByRole('button', { name: 'Ajouter aux favoris' })).toBeEnabled();
  if (text === 'root32') {
    expect(
      await page.evaluate(() => getComputedStyle(document.documentElement).fontSize),
      'the root is not 32px, so this proves nothing',
    ).toBe('32px');
  }
  if (text === 'doubled') {
    const h1 = page.getByRole('heading', { level: 1 });
    const before = (await h1.boundingBox())!.height;
    await page.addStyleTag({ content: DOUBLED });
    await expect
      .poll(async () => (await h1.boundingBox())!.height, { message: 'the text did not double, so this proves nothing' })
      .toBeGreaterThanOrEqual(before * 1.8);
  }
}

/// The page's very end, read in one go: where « Réserver », « Instagram » (the footer's last
/// link) and the footer's foot stand against the bar, and whether a press at « Réserver »'s and
/// « Instagram »'s centres lands on them.
const atTheEnd = (page: Page) =>
  page.evaluate(async () => {
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' });
    await new Promise<void>((done) => requestAnimationFrame(() => setTimeout(done, 0)));
    const answers = (el: Element) => {
      const r = el.getBoundingClientRect();
      const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
      return !!hit && (hit === el || el.contains(hit));
    };
    const bar = document.querySelector('main > :last-child')!;
    const cta = [...bar.querySelectorAll('a')].find((a) => a.textContent?.trim() === 'Réserver')!;
    const insta = [...document.querySelectorAll('footer a')].find((a) => a.textContent?.trim() === 'Instagram')!;
    const b = bar.getBoundingClientRect();
    const c = cta.getBoundingClientRect();
    const i = insta.getBoundingClientRect();
    return {
      y: window.scrollY,
      max: document.documentElement.scrollHeight - innerHeight,
      barTop: b.top,
      barHeight: b.height,
      ctaTop: c.top,
      ctaBottom: c.bottom,
      ctaAnswers: answers(cta),
      instaGap: b.top - i.bottom,
      instaAnswers: answers(insta),
      footerFoot: document.querySelector('footer')!.getBoundingClientRect().bottom,
    };
  });

/// One Tab press at a time from the top of the document, through `main` and then the footer
/// until the focus leaves the page: where each stop stands against the bar. `wholly` is a stop
/// whose part on the screen is all within the bar's rows, so all behind it; `room` is the
/// screen above the bar.
type Stop = { name: string; inBar: boolean; inFooter: boolean; under: number; wholly: boolean; height: number; room: number };
async function tabWalk(page: Page): Promise<Stop[]> {
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
  const stops: Stop[] = [];
  for (let i = 0; i < 200; i++) {
    await page.keyboard.press('Tab');
    const stop = await page.evaluate(() => {
      const el = document.activeElement as HTMLElement | null;
      if (!el || el === document.body) return null;
      const bar = document.querySelector('main > :last-child')!;
      const name = (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 48);
      const b = el.getBoundingClientRect();
      const t = bar.getBoundingClientRect();
      const shown = t.height > 0;
      const inBar = bar.contains(el);
      const top = Math.max(b.top, 0);
      const bottom = Math.min(b.bottom, innerHeight);
      return {
        name,
        inBar,
        inFooter: !!el.closest('footer'),
        under: shown && !inBar ? Math.max(0, Math.min(b.bottom, t.bottom) - Math.max(b.top, t.top)) : 0,
        wholly: shown && !inBar && bottom > top && top >= t.top && bottom <= t.bottom,
        height: b.height,
        room: shown ? t.top : innerHeight,
      };
    });
    // Out of the page, or round to its top again.
    if (stop === null || (stops.length > 0 && stop.name === stops[0].name)) break;
    stops.push(stop);
  }
  test.info().annotations.push({
    type: 'walk',
    description: JSON.stringify({ stops: stops.length, footer: stops.filter((s) => s.inFooter).length }),
  });
  // The walk has to start at the top and reach the map's controls, the FAQ's last question and
  // the footer's last link, or it proved nothing about what it skipped.
  const names = stops.map((s) => s.name);
  expect(names[0], 'the walk did not start at the top').toBe('Aller au contenu');
  expect(names, 'the walk never reached the FAQ').toContain('Faut-il payer un acompte ?');
  expect(names, 'the walk never reached the map').toEqual(expect.arrayContaining(MAP_CONTROLS));
  expect(
    stops.some((s) => s.inBar && s.name === 'Réserver'),
    'the walk never reached the bar’s « Réserver »',
  ).toBe(true);
  expect(
    stops.filter((s) => s.inFooter).at(-1)?.name,
    'the walk did not go through the footer to its last link',
  ).toBe('Instagram');
  return stops;
}

/// Decision 103 (web-swiss-salon.md §3): below `lg` the bar is fixed at the screen's foot, and
/// `BarClearance` gives `<html>` a bottom padding as tall as the bar and a scroll padding of the
/// bar plus 8px while the page shows. Sticky, as #741 first had it, the bar stopped above the
/// footer and left the screen at the page's end (243px of scrolling back for « Réserver » at
/// 320×568, 616px with doubled text); fixed with no room, it stood on « Instagram », which no
/// longer answered a press (measured in plan 103, 27 of 27 settings).
test.describe('a phone: the booking bar (§1.4, decision 103)', () => {
  const PHONES = [
    [390, 844],
    [320, 568],
  ] as const;

  /// D1: at the very end « Réserver » is on the screen and answers, and the footer ends where
  /// the bar starts, so its last link keeps the footer's own bottom padding above the bar.
  const endCase = (width: number, height: number, text: Text) =>
    test(`at ${width}×${height} ${TEXT[text]}, at the page’s very end « Réserver » is on the screen, « Instagram » is clear of the bar, and every footer link answers`, async ({ page }) => {
      await openAt(page, width, height, text);
      const end = await atTheEnd(page);
      test.info().annotations.push({ type: 'end', description: JSON.stringify(end) });
      expect(end.y, 'the page did not scroll, so this proves nothing').toBeGreaterThan(0);
      expect(Math.abs(end.y - end.max), 'not at the page’s very end, so this proves nothing').toBeLessThanOrEqual(1);
      expect(end.ctaTop, '« Réserver » is above the screen').toBeGreaterThanOrEqual(0);
      expect(end.ctaBottom, '« Réserver » is below the screen').toBeLessThanOrEqual(height + 0.5);
      expect(end.ctaAnswers, 'a press at « Réserver »’s centre does not reach it').toBe(true);
      expect(end.instaGap, '« Instagram » reaches the bar').toBeGreaterThan(0);
      expect(end.instaAnswers, 'a press at « Instagram »’s centre does not reach it').toBe(true);
      // The room under the footer is the bar's measured height, not a guess: at the very end
      // the footer's foot meets the bar's top. (After the two above, so that a bar with no room
      // fails on « Instagram » and a room of the wrong height on this.)
      expect(
        Math.abs(end.footerFoot - end.barTop),
        `the footer ends at ${end.footerFoot}, the ${end.barHeight}px bar starts at ${end.barTop}`,
      ).toBeLessThanOrEqual(1);
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
      expect(links.map((l) => l.name), 'the link the bar would stand on').toContain('Instagram');
      expect(links.filter((l) => !l.answers)).toEqual([]);
    });

  for (const [width, height] of PHONES) endCase(width, height, 'normal');
  endCase(320, 568, 'root32');

  for (const [width, height] of PHONES) {
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

  // D4. The browser scrolls a focused control just into view at the screen's foot, under the
  // bar: the FAQ's « Quels sont les tarifs… » was hidden whole at 390 and 1023, and all but
  // 0.3px of « Comment réserver… » at 320 (measured on this page before #741's fix, §1.4). The
  // page's scroll padding, the bar plus 8px, now keeps whatever is focused clear of it, the
  // footer's links included, at every text size (§3.3).
  const walkCase = (width: number, height: number, text: Text) =>
    test(`at ${width}×${height} ${TEXT[text]}, nothing the keyboard reaches, in the page or the footer, stands under the bar`, async ({ page }) => {
      await openAt(page, width, height, text);
      const stops = await tabWalk(page);
      const under = stops.filter((s) => !s.inBar && s.under > 0).map((s) => `« ${s.name} »: ${s.under}px under the bar`);
      expect(under).toEqual([]);
    });
  for (const [width, height] of [...PHONES, [1023, 768]] as const) walkCase(width, height, 'normal');

  /// D5: the room and the scroll padding are the salon page's, written on `<html>` while it
  /// shows; the next page, reached without a full load, must not inherit them (the five
  /// store-linked pages among them).
  test('at 390×844, after a client-side visit to /cgu, <html> carries no room and no scroll padding', async ({ page }) => {
    await openAt(page, 390, 844, 'normal');
    const read = () =>
      page.evaluate(() => {
        const html = document.documentElement;
        const s = getComputedStyle(html);
        return { inline: [html.style.paddingBottom, html.style.scrollPaddingBottom], computed: [s.paddingBottom, s.scrollPaddingBottom] };
      });
    const on = await read();
    const barHeight = (await bar(page).boundingBox())!.height;
    expect(on.computed, 'the salon page did not set both, so this proves nothing').toEqual([`${barHeight}px`, `${barHeight + 8}px`]);
    await page.evaluate(() => {
      (window as unknown as { stillHere: boolean }).stillHere = true;
    });
    await page.locator('footer').getByRole('link', { name: 'Conditions d’utilisation' }).click();
    await page.waitForURL('**/cgu');
    await expect(page.locator('[data-floating-control]')).toHaveCount(0);
    expect(
      await page.evaluate(() => (window as unknown as { stillHere?: boolean }).stillHere),
      'a full load, so this proves nothing about the salon page’s clean-up',
    ).toBe(true);
    await expect.poll(read).toEqual({ inline: ['', ''], computed: ['0px', 'auto'] });
  });

  /// D6: the page's script can arrive after a visitor has reached the footer; the room then
  /// opens below the screen. Whoever is at the very end is kept at the end (§3.3). The page's
  /// chunks are held until the visitor is parked there, then let through.
  for (const [width, height] of PHONES) {
    test(`at ${width}×${height}, a visitor at the very end before the page’s script runs is at the new end once it has, « Instagram » clear of the bar`, async ({ page }) => {
      await hermetic(page);
      await size(page, width, height);
      await routeNextImages(page);
      let release = () => {};
      const held = new Promise<void>((done) => (release = done));
      await page.route('**/_next/static/chunks/**', async (r) => {
        await held;
        await r.continue();
      });
      await page.goto(SALON, { waitUntil: 'domcontentloaded' });
      await expect.poll(() => bar(page).evaluate((el) => getComputedStyle(el).position)).toBe('fixed');
      // The web fonts change the page's height when they land: parked before them, the
      // visitor would no longer be at the end when the script runs.
      await page.evaluate(() => document.fonts.ready);
      const parked = await page.evaluate(() => {
        window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' });
        const b = document.querySelector('main > :last-child')!.getBoundingClientRect();
        const i = [...document.querySelectorAll('footer a')].find((a) => a.textContent?.trim() === 'Instagram')!;
        return {
          y: window.scrollY,
          max: document.documentElement.scrollHeight - innerHeight,
          room: document.documentElement.style.paddingBottom,
          instaUnder: i.getBoundingClientRect().bottom - b.top,
        };
      });
      test.info().annotations.push({ type: 'parked', description: JSON.stringify(parked) });
      expect(parked.y, 'the page did not scroll, so this proves nothing').toBeGreaterThan(0);
      expect(Math.abs(parked.y - parked.max), 'not at the very end, so this proves nothing').toBeLessThanOrEqual(1);
      expect(parked.room, 'the script had already run, so this proves nothing').toBe('');
      expect(parked.instaUnder, '« Instagram » was clear before the script, so this proves nothing').toBeGreaterThan(0);
      release();
      await expect.poll(() => page.evaluate(() => document.documentElement.style.paddingBottom)).not.toBe('');
      const end = await page.evaluate(async () => {
        await new Promise<void>((done) => requestAnimationFrame(() => setTimeout(done, 0)));
        const b = document.querySelector('main > :last-child')!.getBoundingClientRect();
        const insta = [...document.querySelectorAll('footer a')].find((a) => a.textContent?.trim() === 'Instagram')!;
        const i = insta.getBoundingClientRect();
        const hit = document.elementFromPoint(i.x + i.width / 2, i.y + i.height / 2);
        return {
          y: window.scrollY,
          max: document.documentElement.scrollHeight - innerHeight,
          instaGap: b.top - i.bottom,
          instaAnswers: !!hit && (hit === insta || insta.contains(hit)),
        };
      });
      test.info().annotations.push({ type: 'after the script', description: JSON.stringify(end) });
      expect(Math.abs(end.y - end.max), `left at ${end.y}, the page now ends at ${end.max}`).toBeLessThanOrEqual(1);
      expect(end.instaGap, '« Instagram » is under the bar').toBeGreaterThan(0);
      expect(end.instaAnswers, 'a press at « Instagram »’s centre does not reach it').toBe(true);
    });
  }

  /// D7: fixed, the bar would stand at the foot of every printed page (plan 103's first build:
  /// 5 of 5 pages). It is not printed; the hero's « Réserver » is.
  test('at 390×844, printed, the bar is not, and neither is its « À partir de »', async ({ page }) => {
    await openAt(page, 390, 844, 'normal');
    const read = () =>
      page.evaluate(() => ({
        display: getComputedStyle(document.querySelector('main > :last-child')!).display,
        price: document.body.innerText.includes('À partir de'),
      }));
    expect(await read(), 'on the screen the bar and its price show, so this proves nothing').toEqual({ display: 'flex', price: true });
    await page.emulateMedia({ media: 'print' });
    expect(await read()).toEqual({ display: 'none', price: false });
  });

  test.describe(TEXT.doubled, () => {
    test.use(ANDROID);
    endCase(320, 568, 'doubled');
    walkCase(320, 568, 'doubled');

    // WEB-SYSTEM §9's reflow screen: the 137px bar leaves 119px above it, less than some
    // controls are tall (decision 104). None is hidden whole, and one is partly under the bar
    // only when it is too tall to stand, with its 8px, in the room above it.
    test('at 320×256 with doubled text (Android), the keyboard never hides a control whole under the bar', async ({ page }) => {
      await openAt(page, 320, 256, 'doubled');
      const stops = await tabWalk(page);
      const wholly = stops.filter((s) => s.wholly).map((s) => `« ${s.name} »`);
      const partly = stops.filter((s) => !s.inBar && s.under > 0);
      test.info().annotations.push({ type: 'partly under the bar', description: JSON.stringify(partly) });
      expect(wholly, 'hidden whole under the bar').toEqual([]);
      expect(
        partly.filter((s) => s.height + 8 <= s.room).map((s) => `« ${s.name} »: ${s.under}px under, ${s.height}px tall, ${s.room}px of room`),
        'partly under the bar though it fits above it',
      ).toEqual([]);
    });
  });
});

/// Decision 100 at the page's end. While the bar was sticky (#741 at first), it stopped above
/// the footer and climbed through the band the heart's message stands in, and the message
/// climbed with it: up to 224px at 320×568 with doubled text, 92 at normal text (plan 103).
/// Fixed (decision 103), the bar never leaves the screen's foot, so the message wears at the
/// very end the move it wears at rest, and keeps its 8px from the bar (web-swiss-salon.md
/// §3.4). One frame per step, in the page (_message.ts); the figures go into the annotations.
test.describe('a phone: the heart’s message and the bar at the page’s end (decisions 100, 103)', () => {
  test.describe.configure({ timeout: 60_000 });

  /// The move worn at rest, as plan 103 measured it (`summary.fixjs2.<text>.messageRest`, the
  /// heart centred and pressed): 0 at normal text, where the message's home is 15px above the
  /// 65px bar; 65px up at 320×568 with doubled text, where the bar is 137px.
  const REST: Record<string, number> = { 'normal 320x568': 0, 'normal 390x844': 0, 'doubled 320x568': 65 };

  /// The heart centred and pressed: the move the message's region wears, once a frame has run.
  const restMove = async (page: Page) => {
    const heart = page.getByRole('button', { name: 'Ajouter aux favoris' });
    await heart.evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await heart.click();
    const region = page.getByRole('status').filter({ hasText: 'Ajouté aux favoris' });
    await expect(region.locator('div').first()).toBeVisible();
    return region.evaluate(async (el) => {
      await new Promise<void>((done) => requestAnimationFrame(() => setTimeout(done, 0)));
      const live = el as HTMLElement;
      return { dx: parseFloat(live.style.translate) || 0, dy: parseFloat(live.style.marginBottom) || 0 };
    });
  };

  const scan = async (page: Page) => {
    const r = await scanMessage(page, { control: 'bar', heart: 'salon', step: 2, lastPx: 800 });
    const { near: _near, glyphHits, offScreen, nearEdge, annulerCut, pressMisses: _misses, ...figures } = r;
    test.info().annotations.push({
      type: 'scan',
      description: JSON.stringify({
        ...figures,
        glyphHits: glyphHits.length,
        offScreen: offScreen.length,
        nearEdge: nearEdge.length,
        annulerCut: annulerCut.length,
      }),
    });
    return r;
  };

  const restCase = (width: number, height: number, text: Text) =>
    test(`at ${width}×${height} ${TEXT[text]}, over the page’s last 800px, the message wears its resting move and keeps 8px of air from the bar`, async ({ page }) => {
      await openAt(page, width, height, text);
      const rest = await restMove(page);
      const measured = REST[`${text} ${width}x${height}`];
      test.info().annotations.push({ type: 'rest', description: JSON.stringify(rest) });
      expect(Math.abs(rest.dy - measured), `at rest it is ${rest.dy}px up; plan 103 measured ${measured}`).toBeLessThanOrEqual(1);
      expect(rest.dx, 'at rest it slid aside, which plan 103 never saw').toBe(0);
      if (text === 'doubled') {
        expect(rest.dy, 'the bar is clear of the message’s home, so this proves nothing').toBeGreaterThan(0);
      }
      const r = await scan(page);
      expect(r.from + (r.steps - 1) * 2, 'the scan did not reach the page’s end').toBe(r.end);
      expect(r.end - r.from, 'the page is shorter than the scan, so this proves less').toBe(800);
      expect(r.dyMax - rest.dy, `it rose to ${r.dyMax}px at the end, ${rest.dy}px at rest`).toBeLessThanOrEqual(1);
      expect(rest.dy - r.dyMin, `it fell to ${r.dyMin}px at the end, ${rest.dy}px at rest`).toBeLessThanOrEqual(1);
      expect([r.dxMin, r.dxMax], 'it slid aside at the end').toEqual([0, 0]);
      if (text === 'doubled') {
        expect(r.crossed, 'the bar did not stand in the message’s home at every step').toBe(r.steps);
      }
      expect(r.nearCount, `within 8px: ${JSON.stringify(r.near)}`).toBe(0);
    });

  restCase(320, 568, 'normal');
  restCase(390, 844, 'normal');
  test.describe(TEXT.doubled, () => {
    test.use(ANDROID);
    restCase(320, 568, 'doubled');
  });
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
