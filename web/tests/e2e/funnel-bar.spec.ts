import { expect, test, type Page } from '@playwright/test';

import { DOUBLED, hermetic, rootAt32 } from './_message';
import { routeNextImages, serveStubImages } from './_pixel';

/// The booking funnel's phone bar, « total + Confirmer » (parity 2.11), at the funnel's very
/// end (decision 105, docs/design/web-funnel-bar-fit.md §6). Below `lg` the bar is fixed at the
/// screen's foot, and the salon page's `BarClearance`, rendered inside it, gives `<html>` a
/// bottom padding as tall as the bar and a scroll padding of the bar plus 8px while the hub
/// shows. Sticky (#744 until decision 105), the bar was the hub's last child and stopped above
/// the footer: at the very end « Confirmer » had left the screen (up to 604px of scrolling back
/// at normal text, 652 with doubled text, 1,084 with the browser's font at 200 %), and the
/// keyboard left 91 focused controls wholly under it in 48 of 108 settings (plan 105).
///
/// **The bar is found by what it does:** the visible « Confirmer », then its first `fixed` or
/// `sticky` ancestor (type-overflow.spec.ts's `pinnedBar`), never by its classes, so a bar
/// made sticky again is still found, and fails on what it does. **Steps are taken with DOM
/// clicks,** as `walkFunnel` takes them: this file measures where things stand, and a pointer
/// that lands on a bar is not a layout fact.
///
/// **What this cannot see:** whether it looks right, and any browser but Chromium.

const FUNNEL = '/beaute-divine/reserver';

type Text = 'normal' | 'doubled' | 'root32';
const TEXT: Record<Text, string> = {
  normal: 'at normal text',
  doubled: 'with doubled text (Android)',
  root32: 'with a 32px root (a computer’s font at 200 %)',
};
/// Chrome's text scaling on Android needs a touch phone, so the doubled cases sit in a
/// `describe` of their own (salon-page.spec.ts's recipe).
const ANDROID = { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } as const;

/// In the page: the bar that holds the visible « Confirmer », or null.
function barInPage(): HTMLElement | null {
  const confirm = [...document.querySelectorAll('button')].find(
    (b) => b.textContent?.trim() === 'Confirmer' && b.checkVisibility(),
  );
  let bar: HTMLElement | null = confirm ?? null;
  while (bar && !['fixed', 'sticky'].includes(getComputedStyle(bar).position)) bar = bar.parentElement;
  return bar;
}

/// The funnel at a size and a text setting, nothing leaving the machine. Doubled text is on
/// from the document's start, as on a phone set that way, so the compact rule meets it at its
/// first measurement (type-overflow.spec.ts's way); the 32px root is the browser's own font
/// setting.
async function openAt(page: Page, width: number, height: number, text: Text): Promise<void> {
  await hermetic(page);
  await page.setViewportSize({ width, height });
  await serveStubImages(page);
  await routeNextImages(page);
  if (text === 'root32') await rootAt32(page);
  if (text === 'doubled') {
    await page.addInitScript((css) => {
      const add = () => {
        const style = document.createElement('style');
        style.textContent = css;
        document.head.appendChild(style);
      };
      if (document.head) add();
      else document.addEventListener('DOMContentLoaded', add);
    }, DOUBLED);
  }
  await page.goto(FUNNEL);
  await expect(page.getByRole('heading', { level: 1, name: /Réserver chez Beauté Divine/ })).toBeVisible();
  await expectText(page, text);
}

/// The text setting is really on, read now: Chromium's text autosizer, which implements
/// `text-size-adjust`, can drop the doubling when the DOM changes.
async function expectText(page: Page, text: Text): Promise<void> {
  const read = await page.evaluate(() => ({
    root: getComputedStyle(document.documentElement).fontSize,
    step: getComputedStyle(document.querySelector('section > button[aria-expanded] > :first-child')!).fontSize,
  }));
  if (text === 'root32') expect(read.root, 'the root is not 32px, so this proves nothing').toBe('32px');
  if (text === 'doubled') expect(read.step, 'the step titles are not doubled, so this proves nothing').toBe('32px');
  if (text === 'normal') expect(read, 'the text is not at its normal size').toEqual({ root: '16px', step: '16px' });
}

/// A DOM click, as `walkFunnel` clicks.
const tap = (page: Page, role: Parameters<Page['getByRole']>[0], name: string | RegExp) =>
  page
    .getByRole(role, { name })
    .first()
    .evaluate((el) => (el as HTMLElement).click());

/// The hub's last state before the confirm step: a service, « Pas de préférence », the first
/// time. « Confirmer » is then enabled.
async function chooseAll(page: Page): Promise<void> {
  await page.getByRole('checkbox').first().evaluate((el) => (el as HTMLElement).click());
  await tap(page, 'radio', /Pas de préférence/);
  await tap(page, 'button', /^\d{2}:\d{2}$/);
  await expect(page.getByRole('button', { name: /^Date et heure/ })).toContainText(':');
}

/// The funnel's very end, read in one go: where « Confirmer », « Instagram » (the footer's last
/// link) and the footer's foot stand against the bar, and whether a press at « Confirmer »'s and
/// « Instagram »'s centres lands on them.
const atTheEnd = async (page: Page) =>
  page.evaluate(async (bar) => {
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' });
    await new Promise<void>((done) => requestAnimationFrame(() => setTimeout(done, 0)));
    if (!bar) return null;
    const answers = (el: Element) => {
      const r = el.getBoundingClientRect();
      const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
      return !!hit && (hit === el || el.contains(hit));
    };
    const cta = [...bar.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Confirmer')!;
    const insta = [...document.querySelectorAll('footer a')].find((a) => a.textContent?.trim() === 'Instagram')!;
    const b = bar.getBoundingClientRect();
    const c = cta.getBoundingClientRect();
    const i = insta.getBoundingClientRect();
    return {
      screen: [innerWidth, innerHeight],
      y: window.scrollY,
      max: document.documentElement.scrollHeight - innerHeight,
      position: getComputedStyle(bar).position,
      barTop: b.top,
      barHeight: b.height,
      ctaTop: c.top,
      ctaBottom: c.bottom,
      ctaEnabled: !(cta as HTMLButtonElement).disabled,
      ctaAnswers: answers(cta),
      instaGap: b.top - i.bottom,
      instaAnswers: answers(insta),
      footerFoot: document.querySelector('footer')!.getBoundingClientRect().bottom,
    };
  }, await page.evaluateHandle(barInPage));

/// One Tab press at a time from the top of the document, through `main` and then the footer
/// until the focus leaves the page: where each stop stands against the bar. `wholly` is a stop
/// whose part on the screen is all within the bar's rows; `room` is the screen above the bar.
type Stop = { name: string; inBar: boolean; inFooter: boolean; under: number; wholly: boolean; height: number; room: number };
async function tabWalk(page: Page): Promise<Stop[]> {
  await page.evaluate(() => {
    window.scrollTo({ top: 0, behavior: 'instant' });
    const start = document.createElement('span');
    start.tabIndex = -1;
    document.body.prepend(start);
    start.focus();
    start.remove();
  });
  const found = await page.evaluateHandle(barInPage);
  expect(await found.evaluate((b) => !!b), 'no fixed or sticky bar holds the visible « Confirmer »').toBe(true);
  const stops: Stop[] = [];
  for (let i = 0; i < 200; i++) {
    await page.keyboard.press('Tab');
    const stop = await page.evaluate((bar) => {
      const el = document.activeElement as HTMLElement | null;
      if (!el || el === document.body || !bar) return null;
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
    }, found);
    // Out of the page, or round to its top again.
    if (stop === null || (stops.length > 0 && stop.name === stops[0].name)) break;
    stops.push(stop);
  }
  test.info().annotations.push({
    type: 'walk',
    description: JSON.stringify({ stops: stops.length, footer: stops.filter((s) => s.inFooter).length }),
  });
  // The walk has to start at the top, pass the steps and the bar's « Confirmer », and go
  // through the footer to its last link, or it proved nothing about what it skipped.
  const names = stops.map((s) => s.name);
  expect(names[0], 'the walk did not start at the top').toBe('Aller au contenu');
  expect(names.some((n) => n.startsWith('Prestations')), 'the walk never reached the steps').toBe(true);
  expect(names.some((n) => /^\d{2}:\d{2}$/.test(n)), 'the walk never reached a time').toBe(true);
  expect(
    stops.some((s) => s.inBar && s.name === 'Confirmer'),
    'the walk never reached the bar’s « Confirmer »',
  ).toBe(true);
  expect(
    stops.filter((s) => s.inFooter).at(-1)?.name,
    'the walk did not go through the footer to its last link',
  ).toBe('Instagram');
  return stops;
}

const roomOn = (page: Page) =>
  page.evaluate(() => {
    const html = document.documentElement;
    const s = getComputedStyle(html);
    return { inline: [html.style.paddingBottom, html.style.scrollPaddingBottom], computed: [s.paddingBottom, s.scrollPaddingBottom] };
  });

test.describe('the booking funnel’s phone bar at the funnel’s end (decision 105)', () => {
  const PHONES = [
    [390, 844],
    [320, 568],
  ] as const;

  /// F1: at the very end « Confirmer » is on the screen and answers, and the footer ends where
  /// the bar starts, so its last link keeps the footer's own bottom padding above the bar.
  const endCase = (width: number, height: number, text: Text) =>
    test(`at ${width}×${height} ${TEXT[text]}, at the funnel’s very end « Confirmer » is on the screen and answers, « Instagram » is clear of the bar, and every footer link answers`, async ({ page }) => {
      await openAt(page, width, height, text);
      await chooseAll(page);
      await expectText(page, text);
      const end = await atTheEnd(page);
      test.info().annotations.push({ type: 'end', description: JSON.stringify(end) });
      expect(end, 'no fixed or sticky bar holds the visible « Confirmer »').not.toBeNull();
      expect(end!.screen, 'the layout is not the screen, so the bar is placed off it').toEqual([width, height]);
      expect(end!.y, 'the page did not scroll, so this proves nothing').toBeGreaterThan(0);
      expect(Math.abs(end!.y - end!.max), 'not at the page’s very end, so this proves nothing').toBeLessThanOrEqual(1);
      expect(end!.ctaEnabled, '« Confirmer » is not enabled, so this proves nothing').toBe(true);
      expect(end!.ctaTop, '« Confirmer » is above the screen').toBeGreaterThanOrEqual(0);
      expect(end!.ctaBottom, '« Confirmer » is below the screen').toBeLessThanOrEqual(height + 0.5);
      expect(end!.ctaAnswers, 'a press at « Confirmer »’s centre does not reach it').toBe(true);
      expect(end!.instaGap, '« Instagram » reaches the bar').toBeGreaterThan(0);
      expect(end!.instaAnswers, 'a press at « Instagram »’s centre does not reach it').toBe(true);
      // The room under the footer is the bar's measured height, not a guess: at the very end
      // the footer's foot meets the bar's top. (After the two above, so that a bar with no room
      // fails on « Instagram » and a room of the wrong height on this.)
      expect(
        Math.abs(end!.footerFoot - end!.barTop),
        `the footer ends at ${end!.footerFoot}, the ${end!.barHeight}px bar starts at ${end!.barTop}`,
      ).toBeLessThanOrEqual(1);
      // Last link first, each brought on-screen only if it is not: `elementFromPoint` answers
      // nothing off the screen.
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

  /// F2: the browser scrolls a focused control just into view at the screen's foot, which is
  /// under a pinned bar; the scroll padding, the bar plus 8px, keeps it clear. None is hidden
  /// whole, and one is partly under the bar only when it is too tall to stand, with its 8px, in
  /// the room above it.
  const walkCase = (width: number, height: number) =>
    test(`at ${width}×${height} with doubled text (Android), the keyboard never hides a control under the bar, in the steps or the footer`, async ({ page }) => {
      await openAt(page, width, height, 'doubled');
      await chooseAll(page);
      await expectText(page, 'doubled');
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

  /// F3: the page's script can arrive after a visitor has reached the footer; the room then
  /// opens below the screen. Whoever is at the very end is kept at the end. The page's chunks
  /// are held until the visitor is parked there, then let through.
  for (const [width, height] of PHONES) {
    test(`at ${width}×${height}, a visitor at the funnel’s very end before the page’s script runs is at the new end once it has, « Instagram » clear of the bar`, async ({ page }) => {
      await hermetic(page);
      await page.setViewportSize({ width, height });
      await serveStubImages(page);
      await routeNextImages(page);
      let release = () => {};
      const held = new Promise<void>((done) => (release = done));
      await page.route('**/_next/static/chunks/**', async (r) => {
        await held;
        await r.continue();
      });
      await page.goto(FUNNEL, { waitUntil: 'domcontentloaded' });
      await expect
        .poll(async () => (await page.evaluateHandle(barInPage)).evaluate((b) => (b ? getComputedStyle(b).position : null)))
        .toBe('fixed');
      // The web fonts change the page's height when they land: parked before them, the
      // visitor would no longer be at the end when the script runs.
      await page.evaluate(() => document.fonts.ready);
      const parked = await page.evaluate((bar) => {
        window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' });
        const b = bar!.getBoundingClientRect();
        const i = [...document.querySelectorAll('footer a')].find((a) => a.textContent?.trim() === 'Instagram')!;
        return {
          y: window.scrollY,
          max: document.documentElement.scrollHeight - innerHeight,
          room: document.documentElement.style.paddingBottom,
          instaUnder: i.getBoundingClientRect().bottom - b.top,
        };
      }, await page.evaluateHandle(barInPage));
      test.info().annotations.push({ type: 'parked', description: JSON.stringify(parked) });
      expect(parked.y, 'the page did not scroll, so this proves nothing').toBeGreaterThan(0);
      expect(Math.abs(parked.y - parked.max), 'not at the very end, so this proves nothing').toBeLessThanOrEqual(1);
      expect(parked.room, 'the script had already run, so this proves nothing').toBe('');
      expect(parked.instaUnder, '« Instagram » was clear before the script, so this proves nothing').toBeGreaterThan(0);
      release();
      await expect.poll(() => page.evaluate(() => document.documentElement.style.paddingBottom)).not.toBe('');
      const end = await page.evaluate(async (bar) => {
        await new Promise<void>((done) => requestAnimationFrame(() => setTimeout(done, 0)));
        const b = bar!.getBoundingClientRect();
        const insta = [...document.querySelectorAll('footer a')].find((a) => a.textContent?.trim() === 'Instagram')!;
        const i = insta.getBoundingClientRect();
        const hit = document.elementFromPoint(i.x + i.width / 2, i.y + i.height / 2);
        return {
          y: window.scrollY,
          max: document.documentElement.scrollHeight - innerHeight,
          instaGap: b.top - i.bottom,
          instaAnswers: !!hit && (hit === insta || insta.contains(hit)),
        };
      }, await page.evaluateHandle(barInPage));
      test.info().annotations.push({ type: 'after the script', description: JSON.stringify(end) });
      expect(Math.abs(end.y - end.max), `left at ${end.y}, the page now ends at ${end.max}`).toBeLessThanOrEqual(1);
      expect(end.instaGap, '« Instagram » is under the bar').toBeGreaterThan(0);
      expect(end.instaAnswers, 'a press at « Instagram »’s centre does not reach it').toBe(true);
    });
  }

  /// F4: fixed, the bar would stand at the foot of every printed page. It is not printed, and no
  /// « Confirmer » shows in print (the side panel's is a computer's, from `lg`).
  test('at 390×844, printed, the bar is not, and no « Confirmer » shows', async ({ page }) => {
    await openAt(page, 390, 844, 'normal');
    const bar = await page.evaluateHandle(barInPage);
    const read = () =>
      bar.evaluate((el) => ({
        display: el ? getComputedStyle(el).display : 'no bar',
        confirm: [...document.querySelectorAll('button')].filter(
          (b) => b.textContent?.trim() === 'Confirmer' && b.checkVisibility(),
        ).length,
      }));
    expect(await read(), 'on the screen the bar and its « Confirmer » show, so this proves nothing').toEqual({ display: 'block', confirm: 1 });
    await page.emulateMedia({ media: 'print' });
    expect(await read()).toEqual({ display: 'none', confirm: 0 });
  });

  /// F6: the confirm step has no bar (its button is in the page, as the app's confirmation
  /// screen has it), so it must not inherit the hub's room: pressing « Confirmer » unmounts the
  /// bar, and `BarClearance` takes both styles off.
  test('at 390×844, once « Confirmer » is pressed, the confirm step carries no room and no scroll padding', async ({ page }) => {
    await openAt(page, 390, 844, 'normal');
    await chooseAll(page);
    const height = await (await page.evaluateHandle(barInPage)).evaluate((b) => b!.getBoundingClientRect().height);
    expect(await roomOn(page), 'the hub did not set both, so this proves nothing').toEqual({
      inline: [`${height}px`, `${height + 8}px`],
      computed: [`${height}px`, `${height + 8}px`],
    });
    await page.getByRole('button', { name: 'Confirmer', exact: true }).last().click();
    await expect(page.getByRole('heading', { level: 2, name: 'Confirmer', exact: true })).toBeVisible();
    await expect.poll(() => roomOn(page)).toEqual({ inline: ['', ''], computed: ['0px', 'auto'] });
  });

  test.describe(TEXT.doubled, () => {
    test.use(ANDROID);
    endCase(320, 568, 'doubled');
    walkCase(320, 568);
    walkCase(320, 256);

    /// F5: the compact rule (web-funnel-bar-fit.md §2) and the room. With doubled text at
    /// 320×568 the bar is full before a choice (113px: « Confirmer » and « 0 FCFA »); a service
    /// makes the full bar take more than a quarter of the screen, so it keeps « Confirmer »
    /// alone, 73px. The room is the bar's height after the switch, not before it.
    test('at 320×568 with doubled text (Android), when the bar turns compact the room follows it', async ({ page }) => {
      await openAt(page, 320, 568, 'doubled');
      const barRead = async () =>
        (await page.evaluateHandle(barInPage)).evaluate((bar) => ({
          height: bar!.getBoundingClientRect().height,
          total: /FCFA/.test(bar!.textContent ?? ''),
        }));
      const before = await barRead();
      expect(before.total, 'the bar is compact before a choice, so this proves nothing').toBe(true);
      expect(await roomOn(page), 'no room for the full bar').toEqual({
        inline: [`${before.height}px`, `${before.height + 8}px`],
        computed: [`${before.height}px`, `${before.height + 8}px`],
      });
      await page.getByRole('checkbox').first().evaluate((el) => (el as HTMLElement).click());
      await expect.poll(async () => (await barRead()).total, { message: 'the bar did not turn compact, so this proves nothing' }).toBe(false);
      await expectText(page, 'doubled');
      const after = await barRead();
      expect(after.height, 'the compact bar kept the full bar’s height, so this proves nothing').not.toBe(before.height);
      await expect.poll(() => roomOn(page)).toEqual({
        inline: [`${after.height}px`, `${after.height + 8}px`],
        computed: [`${after.height}px`, `${after.height + 8}px`],
      });
      const end = await atTheEnd(page);
      test.info().annotations.push({ type: 'switch', description: JSON.stringify({ before, after, end }) });
      expect(end!.ctaTop, '« Confirmer » is above the screen').toBeGreaterThanOrEqual(0);
      expect(end!.ctaBottom, '« Confirmer » is below the screen').toBeLessThanOrEqual(568.5);
      expect(end!.instaGap, '« Instagram » reaches the bar').toBeGreaterThan(0);
      expect(Math.abs(end!.footerFoot - end!.barTop), 'the room is not the compact bar’s height').toBeLessThanOrEqual(1);
    });
  });
});
