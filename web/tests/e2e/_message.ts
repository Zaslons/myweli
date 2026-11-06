import type { Page } from '@playwright/test';

/// The favourite's message against a floating control, read in a real browser
/// (docs/design/web-swiss-salon.md §2.3, §2.9; BACKLOG 100). The toast places its pill in a
/// frame callback after each scroll, so a read straight after `scrollTo` sees the pill where
/// the last frame left it. Each step here is one frame: `scrollTo`, then a frame callback,
/// then the task after it, by which time the browser has fired the scroll and run every frame
/// callback of that frame, the toast's own included. What is read is what that frame shows.
///
/// The loop runs inside the page, so a step costs one frame and no round trip: a 4,000 px
/// page in 4 px steps is about 1,000 frames.
///
/// **The control is found by what it is** (« Carte » by its word, the salon page's bar as the
/// last thing in `main`), never by `data-floating-control`, the mark the toast reads: a guard
/// that found it by the mark could not go red when the mark goes.

type Box = { left: number; top: number; right: number; bottom: number };
type Met = { s: number; pill: Box; control: Box; dx: number; dy: number };

export type MessageScan = {
  from: number;
  end: number;
  steps: number;
  /// Steps where the control stood within 8px of the message's home: where it had to move.
  crossed: number;
  /// Steps where the pill and the control came within 8px of each other (the first five kept).
  nearCount: number;
  near: Met[];
  /// Steps where their boxes overlapped.
  overlapCount: number;
  /// Steps where a press at « Carte »'s centre would not have reached it.
  pressMisses: number[];
  moved: number;
  slid: number;
  rose: number;
  dropped: number;
  maxSlide: number;
  maxRise: number;
  maxDrop: number;
  /// Steps where the pill covered any part of a ♡/♥ glyph's own text box (not its tap area).
  glyphHits: number[];
  /// Steps where the pill was not whole on the screen.
  offScreen: number[];
  /// Steps where a move had brought the pill nearer the screen's edge than `m`, 16px.
  nearEdge: number[];
  /// Steps where « Annuler » was not wholly on the screen.
  annulerCut: number[];
  /// Steps where the control's foot stood above the screen's foot: stopped above the footer.
  controlRaised: number;
  presses: number;
  ms: number;
};

export type ScanArgs = {
  /// « Carte » on `/recherche`, or the salon page's booking bar.
  control: 'carte' | 'bar';
  /// The first row's heart on `/recherche`, or the salon page's own.
  heart: 'row' | 'salon';
  step: number;
  /// Scan only the page's last N px; null scans it all.
  lastPx: number | null;
};

/// Press the heart (the message is « Ajouté aux favoris », with « Annuler »), then scroll the
/// page in `step` px steps, one frame each, pressing again once the message is older than 7s
/// (it lasts 10s). Every press leaves the salon favourited, so the message is always the same.
export const scanMessage = (page: Page, args: ScanArgs): Promise<MessageScan> => page.evaluate(scanInPage, args);

async function scanInPage({ control, heart, step, lastPx }: ScanArgs): Promise<MessageScan> {
  const AIR = 8;
  const EDGE = 16;
  const t0 = performance.now();
  const frame = () => new Promise<void>((done) => requestAnimationFrame(() => setTimeout(done, 0)));
  const sleep = (ms: number) => new Promise<void>((done) => setTimeout(done, ms));
  const meets = (a: Box, b: Box, gap: number) =>
    b.left - gap < a.right && a.left < b.right + gap && b.top - gap < a.bottom && a.top < b.bottom + gap;
  const plain = (r: Box): Box => ({ left: r.left, top: r.top, right: r.right, bottom: r.bottom });

  const findControl = (): Element | null =>
    control === 'carte'
      ? ([...document.querySelectorAll('main button')].find((b) => b.textContent?.trim() === 'Carte') ?? null)
      : document.querySelector('main > :last-child');
  const findHeart = (): HTMLButtonElement | null =>
    heart === 'row'
      ? document.querySelector<HTMLButtonElement>('main button[aria-label$="favoris"]')
      : ([...document.querySelectorAll<HTMLButtonElement>('main button[aria-pressed]')].find((b) =>
          /favori/i.test(b.textContent ?? ''),
        ) ?? null);
  const isOn = (h: HTMLButtonElement) =>
    heart === 'row' ? /^Retirer/.test(h.getAttribute('aria-label') ?? '') : h.getAttribute('aria-pressed') === 'true';

  let lastPress = -Infinity;
  let presses = 0;
  const press = async () => {
    let h = findHeart();
    if (!h) throw new Error('no heart to press');
    if (isOn(h)) {
      h.click();
      await sleep(450);
      h = findHeart()!;
    }
    h.click();
    await sleep(450);
    lastPress = performance.now();
    presses++;
  };

  /// Every visible ♡/♥ glyph outside the toast: its own text box.
  const glyphs = (region: Element): Box[] => {
    const out: Box[] = [];
    for (const b of document.querySelectorAll('button')) {
      if (region.contains(b) || !/[♡♥]/.test(b.textContent ?? '')) continue;
      const walker = document.createTreeWalker(b, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const i = (n.textContent ?? '').search(/[♡♥]/);
        if (i < 0) continue;
        const range = document.createRange();
        range.setStart(n, i);
        range.setEnd(n, i + 1);
        const g = range.getBoundingClientRect();
        if (g.width && g.bottom > 0 && g.top < innerHeight) out.push(plain(g));
        break;
      }
    }
    return out;
  };

  const end = document.documentElement.scrollHeight - innerHeight;
  const from = lastPx == null ? 0 : Math.max(0, end - lastPx);
  window.scrollTo({ top: from, behavior: 'instant' });
  await frame();
  await press();
  const region = [...document.querySelectorAll('[role="status"]')].find((r) =>
    (r.textContent ?? '').includes('Ajouté aux favoris'),
  );
  if (!region) throw new Error('the message never showed');

  const res: MessageScan = {
    from, end, steps: 0, crossed: 0, nearCount: 0, near: [], overlapCount: 0, pressMisses: [],
    moved: 0, slid: 0, rose: 0, dropped: 0, maxSlide: 0, maxRise: 0, maxDrop: 0,
    glyphHits: [], offScreen: [], nearEdge: [], annulerCut: [], controlRaised: 0, presses: 0, ms: 0,
  };
  for (let s = from; s <= end; s += step) {
    if (!region.firstElementChild || performance.now() - lastPress > 7000) await press();
    window.scrollTo({ top: s, behavior: 'instant' });
    await frame();
    const pill = region.firstElementChild;
    if (!pill) throw new Error(`the message went at ${s}`);
    const p = plain(pill.getBoundingClientRect());
    const live = region as HTMLElement;
    // The move the pill wears (Toast.tsx writes it on the region), taken off to find its home.
    const dx = parseFloat(live.style.translate) || 0;
    const dy = parseFloat(live.style.marginBottom) || 0;
    const home: Box = { left: p.left - dx, right: p.right - dx, top: p.top + dy, bottom: p.bottom + dy };
    const H = innerHeight;
    const W = document.documentElement.clientWidth;
    const el = findControl();
    const r = el?.getBoundingClientRect();
    // The control on the screen, or null.
    const c = el && r && r.right > r.left && r.bottom > 0 && r.top < H ? plain(r) : null;
    res.steps++;
    if (c && c.bottom < H - 0.5) res.controlRaised++;
    if (c && meets(home, c, AIR)) res.crossed++;
    if (c && meets(p, c, AIR)) {
      res.nearCount++;
      if (res.near.length < 5) res.near.push({ s, pill: p, control: c, dx, dy });
    }
    if (c && meets(p, c, 0)) res.overlapCount++;
    if (control === 'carte' && el && c) {
      const cx = (c.left + c.right) / 2;
      const cy = (c.top + c.bottom) / 2;
      if (cy > 0 && cy < H) {
        const hit = document.elementFromPoint(cx, cy);
        if (!hit || !(hit === el || el.contains(hit))) res.pressMisses.push(s);
      }
    }
    if (dx || dy) res.moved++;
    if (dx) {
      res.slid++;
      res.maxSlide = Math.max(res.maxSlide, Math.abs(dx));
    }
    if (dy > 0) {
      res.rose++;
      res.maxRise = Math.max(res.maxRise, dy);
    }
    if (dy < 0) {
      res.dropped++;
      res.maxDrop = Math.max(res.maxDrop, -dy);
    }
    if (p.top < 0 || p.bottom > H || p.left < 0 || p.right > W) res.offScreen.push(s);
    if (
      (dy > 0 && p.top < EDGE - 0.5) ||
      (dy < 0 && p.bottom > H - EDGE + 0.5) ||
      (dx > 0 && p.right > W - EDGE + 0.5) ||
      (dx < 0 && p.left < EDGE - 0.5)
    )
      res.nearEdge.push(s);
    const undo = pill.querySelector('button')?.getBoundingClientRect();
    if (!undo || undo.top < 0 || undo.bottom > H || undo.left < 0 || undo.right > W) res.annulerCut.push(s);
    if (glyphs(region).some((g) => meets(p, g, 0))) res.glyphHits.push(s);
  }
  res.presses = presses;
  res.ms = Math.round(performance.now() - t0);
  return res;
}

/// The favourites are answered here, never by the stub: a read says « none yet » (so the heart
/// is enabled without a sign-in) and every write succeeds.
export const answerFavourites = (page: Page) =>
  page.route('**/api/me/favorites**', (r) =>
    r.request().method() === 'GET'
      ? r.fulfill({ status: 200, contentType: 'application/json', body: '{"favorites":[]}' })
      : r.fulfill({ status: 204 }),
  );

/// Nothing leaves the machine: every request to a host other than this one is aborted, and a
/// popup the page opens is closed at once. Popups only: axe opens a blank page of its own in the
/// same context to finish its run, and closing every new page took that one too.
export async function hermetic(page: Page): Promise<void> {
  await page.context().route(
    (url) => /^https?:$/.test(url.protocol) && !['127.0.0.1', 'localhost'].includes(url.hostname),
    (r) => r.abort(),
  );
  page.on('popup', (popup) => void popup.close());
}

/// Chrome's own text scaling on Android, which is what `text-size-adjust` does on a mobile page
/// (site-look.spec.ts's « at 200% text »). Needs `isMobile`.
export const DOUBLED = 'html { -webkit-text-size-adjust: 200% !important; text-size-adjust: 200% !important; }';

/// A computer browser's font size at 200 %: a 32px root (salon-page.spec.ts's recipe).
export async function rootAt32(page: Page): Promise<void> {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Page.setFontSizes', { fontSizes: { standard: 32, fixed: 26 } });
}
