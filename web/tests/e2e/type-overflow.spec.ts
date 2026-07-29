import { expect, test, type Page } from '@playwright/test';

import { signInConsumer, signInPro } from './_auth';

/// B2b — the type scale must not overflow anything (WEB-SYSTEM §3).
///
/// Why this file exists: B2b deliberately makes text wider (it mirrors the app's
/// `letterSpacing`, which the web never had) and grows 51 headings to 22px. French
/// copy is long and at 375px there is nowhere for it to go. The unit suite asserts
/// roles and text, never geometry; there is no screenshot harness on web.
///
/// **BE HONEST ABOUT WHAT THIS CATCHES.** I mutation-tested it: cranking
/// `bodyMedium`'s tracking from 0.25px to **6px** does NOT make it fail — because
/// text *wraps*. A wider string takes more lines; it does not overflow. So this
/// cannot see tracking, and that is the finding, not a gap: extra tracking reflows,
/// and reflow is not a bug.
///
/// What it does catch is the class of bug that *is* a bug — an element wide enough
/// to push the page sideways (a `nowrap` heading, a fixed-width chrome element that
/// stopped fitting). That is a real failure mode for the 18→22px sidebar wordmark
/// and the hero, so the guard is worth its seconds.
///
/// The journal test below is the one that bites hardest: it asserts an exact
/// computed line-height, and it goes red the moment `leading-tight` stops winning.

test.use({ viewport: { width: 375, height: 812 } });

/// B9 — a route this file measures. `auth` and `setup` are what turned the
/// authed pages from hand-written exceptions into matrix entries.
///
/// **The exceptions are why the gate was blind.** Before B9 this file had
/// `PUBLIC_ROUTES` plus two bespoke `test()`s that each re-implemented the
/// login. One of them stood on `/pro/rendez-vous` — the page carrying the first
/// of five tab strips — and asserted a computed `line-height` and nothing else.
/// Both registers recorded the reason as "it runs `PUBLIC_ROUTES` only"; the
/// truth was worse, because the gate was already there.
type Route = {
  name: string;
  url: string;
  /// The vacuity guard AND the "page rendered" signal — see the loop below.
  anchor: string | RegExp;
  auth?: 'pro' | 'consumer';
  /// Reaches state the URL cannot. Strip #2 lives behind a « Liste » click:
  /// `RendezVousClient`'s default view is `journal`, so a test that merely
  /// loads the page never renders the tabs it is there to measure.
  setup?: (page: Page) => Promise<void>;
};

const PUBLIC_ROUTES: [name: string, url: string, anchor: string | RegExp][] = [
  ['the marketing home — all 15 of the h2s that grew 20 → 22px live here', '/', /Réservez beauté/],
  ['discovery', '/recherche?commune=Cocody', /Salons à Cocody/],
  // B8 caught this route VACUOUS: the stub's salon is `beaute-divine` and the
  // canonical path is `/{slug}` — `/salon/salon-excellence` had been scanning
  // the 404 page (which also doesn't overflow) since the slug scheme changed.
  ['a salon page — the h1 that went 30 → 28px', '/beaute-divine', 'Beauté Divine'],
  // B8: the auth prompt copy reads at 16 and the e-mail field types at 16 —
  // the first route where both of B8's growths meet a 375px viewport.
  ['the consumer connexion — B8 copy + a 16px field', '/connexion', /Connexion|Se connecter|e-mail/i],
  // L1: the document a store reviewer actually opens, and the only one whose
  // prose is long enough to find a wrapping bug. The anchor is the vacuity
  // guard this file's own header demands — a wrong URL scans the 404 page,
  // which also does not overflow.
  ['the account-deletion page — the one a reviewer opens on a phone', '/suppression-compte', /Supprimer votre compte/i],
];

/// The document must not scroll sideways. This is the blunt, honest check: if any
/// string got wide enough to push the layout, the body reports it here.
async function noHorizontalScroll(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const d = document.documentElement;
    // +1 for sub-pixel rounding; we are hunting real overflow, not 0.5px.
    return d.scrollWidth <= d.clientWidth + 1;
  });
}

/// Any element whose own text spills horizontally out of its box. Skips the
/// legitimately-scrollable (the journal grid, the roster table, chip strips) by
/// honouring `overflow-x`.
async function overflowingText(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const bad: string[] = [];
    for (const el of Array.from(document.querySelectorAll<HTMLElement>('h1,h2,h3,p,span,button,a,label'))) {
      if (!el.textContent?.trim()) continue;
      const s = getComputedStyle(el);
      if (s.overflowX !== 'visible') continue; // it is meant to scroll/clip
      if (s.textOverflow === 'ellipsis') continue; // it is meant to truncate
      if (el.scrollWidth > el.clientWidth + 1) {
        bad.push(`<${el.tagName.toLowerCase()}> "${el.textContent.trim().slice(0, 40)}" ${el.scrollWidth}>${el.clientWidth}`);
      }
    }
    return bad;
  });
}

/// A **non-wrapping flex row whose items do not fit it** (B9).
///
/// The third defect class this file measures, and neither of the other two can
/// see it:
///
/// - `overflowingText` walks text elements, and a flex item's `min-width`
///   computes to `auto` — so each `<button>` in a tab strip is sized exactly to
///   its own text and has `scrollWidth === clientWidth`. It spills its PARENT,
///   never itself.
/// - `noHorizontalScroll` sees it only once the spill reaches the viewport. A
///   strip inside a capped or padded column can overrun its container by 40px
///   and never move the document.
///
/// So the assertion is the one that matches the mechanism: sum the in-flow
/// children of a `nowrap` flex container and compare with the container.
/// Absolutely-positioned children are out of flow and excluded — including them
/// is what made a blanket `div` sweep false-positive on five public routes.
/// Anything that declares `overflow-x` is opted out, exactly as above: a row
/// that says it scrolls is not a row that broke.
async function overflowingFlexRows(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const bad: string[] = [];
    // `childElementCount >= 2` FIRST, and it is not a micro-optimisation: a
    // `getComputedStyle` on every node of a pro page is expensive enough to
    // push sibling spec files past the 30s timeout, which showed up as two
    // unrelated tests flaking on two consecutive runs. A row needs two items
    // to be a strip, so the cheap DOM property is also the correct filter.
    const candidates = Array.from(
      document.querySelectorAll<HTMLElement>('*'),
    ).filter((el) => el.childElementCount >= 2);
    for (const el of candidates) {
      const s = getComputedStyle(el);
      if (s.display !== 'flex' && s.display !== 'inline-flex') continue;
      if (s.flexWrap !== 'nowrap') continue; // it is allowed to wrap
      if (s.overflowX !== 'visible') continue; // it is meant to scroll/clip
      if (s.flexDirection !== 'row' && s.flexDirection !== 'row-reverse') continue;

      let need = 0;
      let items = 0;
      for (const child of Array.from(el.children) as HTMLElement[]) {
        const cs = getComputedStyle(child);
        if (cs.position === 'absolute' || cs.position === 'fixed') continue;
        if (cs.display === 'none') continue;
        const cb = child.getBoundingClientRect();
        const ml = parseFloat(cs.marginLeft) || 0;
        const mr = parseFloat(cs.marginRight) || 0;
        need += cb.width + ml + mr;
        items += 1;
      }
      if (items < 2) continue; // a one-item row cannot be a strip
      const gap = (parseFloat(s.columnGap) || 0) * (items - 1);
      const pad = (parseFloat(s.paddingLeft) || 0) + (parseFloat(s.paddingRight) || 0);
      const have = el.clientWidth - pad;
      if (need + gap > have + 1) {
        bad.push(
          `<${el.tagName.toLowerCase()} class="${el.className}"> ` +
            `${items} items need ${Math.round(need + gap)} of ${Math.round(have)}`,
        );
      }
    }
    return bad;
  });
}

for (const [name, url, anchor] of PUBLIC_ROUTES) {
  test(`${name} — no horizontal overflow at 375px`, async ({ page }) => {
    await page.goto(url);
    // The content anchor is BOTH the "page rendered" signal AND the vacuity
    // guard — waiting on it beats `networkidle`, which never fires on the
    // image-bearing routes (the stub's salon photos point at an unresolvable
    // `cdn.stub`, so `next/image` keeps the network busy past the 30s
    // timeout). B8 found the salon route had been silently scanning the 404
    // page for months (a slug rename left it 404, and the 404 page doesn't
    // overflow either — a green gate measuring nothing); a heading unique to
    // the REAL page makes that vacuity loud.
    // `.first()`: some routes carry a responsive heading twin (a visible h1 +
    // an sr-only lg:hidden one); one is enough to prove the DOM is right.
    await expect(
      page.getByRole('heading', { name: anchor }).first(),
      `${url} did not render its own page (wrong DOM — vacuous scan)`,
    ).toBeVisible();
    expect(await noHorizontalScroll(page), `the page scrolls sideways at 375px`).toBe(true);
    expect(await overflowingText(page), 'text spills out of its own box').toEqual([]);
  });
}

/// The authed half of the matrix (B9).
///
/// Every one of these was previously either a bespoke `test()` with its own
/// copy of the login, or — for four of the five tab strips — not visited at all.
const AUTHED_ROUTES: Route[] = [
  {
    // Pre-B9 this was a hand-written test and it DID assert both. Kept as the
    // proof that the matrix form loses nothing: DayHoursEditor is the densest
    // field row in the product (checkbox + two time inputs at `px-s py-xs`),
    // and B8 grew the typed text 14 → 16.
    //
    // HONEST NOTE, carried over: `overflowingText()` never queries inputs (a
    // field clips its own value by design), so the page-level scrollWidth
    // check is the real assertion here; the per-element pass covers the labels
    // around them.
    name: 'disponibilités — the tightest input geometry survives 16px digits (B8)',
    url: '/pro/disponibilites',
    anchor: 'Disponibilités',
    auth: 'pro',
  },
  {
    // **Strip #1** — « Journée » · « Calendrier » · « Liste ». Pre-B9 this page
    // was visited and measured for a `line-height` only.
    name: 'the pro agenda — the view switcher (strip #1)',
    url: '/pro/rendez-vous',
    anchor: 'Rendez-vous',
    auth: 'pro',
  },
  {
    // **Strip #2** — « Aujourd'hui » · « À venir » · « En attente » · « Tous »,
    // the widest of the five and the only one computed to overflow at 375.
    // It renders only when `view === 'list'`, and the default is `journal`.
    name: 'the pro agenda, list view — the four status tabs (strip #2)',
    url: '/pro/rendez-vous',
    anchor: 'Rendez-vous',
    auth: 'pro',
    setup: async (page) => {
      await page.getByRole('button', { name: 'Liste' }).click();
    },
  },
  {
    // **Strip #3** — « Services » · « Employés ».
    name: 'the pro catalogue — services vs employés (strip #3)',
    url: '/pro/catalogue',
    anchor: /Catalogue|Services/,
    auth: 'pro',
  },
  {
    // **Strip #4** — « Photos » · « Avant / Après ».
    name: 'the pro media library — photos vs avant/après (strip #4)',
    url: '/pro/medias',
    anchor: 'Médias',
    auth: 'pro',
  },
  {
    // **Strip #5** — « À venir » · « Passés » · « Annulés ». The only strip on
    // the consumer surface, and the only authed consumer route this file has
    // ever measured.
    name: 'the consumer account — the booking tabs (strip #5)',
    url: '/mon-compte',
    anchor: 'Mon compte',
    auth: 'consumer',
  },
];

for (const route of AUTHED_ROUTES) {
  test(`${route.name} — no horizontal overflow at 375px`, async ({ page }) => {
    if (route.auth === 'pro') await signInPro(page);
    else await signInConsumer(page);

    await page.goto(route.url);
    await expect(
      page.getByRole('heading', { name: route.anchor }).first(),
      `${route.url} did not render its own page (wrong DOM — vacuous scan)`,
    ).toBeVisible();
    await route.setup?.(page);

    expect(await noHorizontalScroll(page), 'the page scrolls sideways at 375px').toBe(true);
    expect(await overflowingText(page), 'text spills out of its own box').toEqual([]);
    expect(
      await overflowingFlexRows(page),
      'a nowrap flex row does not fit its own container',
    ).toEqual([]);
  });
}

test('the pro journal — the 11px block label still fits its ~15px row', async ({
  page,
}) => {
  // The tightest box in the product, and the one B2b touched most riskily:
  // `text-[11px]` → `text-labelSmall`, which carries a 16px line the arbitrary
  // value never had. `leading-tight` overrides it back to 13.75px — this is what
  // proves that actually happens in a browser rather than only in the cascade.
  await signInPro(page);
  await page.goto('/pro/rendez-vous');
  await expect(page.getByText('Awa').first()).toBeVisible();

  const line = await page
    .getByRole('button', { name: /Koffi/ })
    .first()
    .evaluate((el) => getComputedStyle(el).lineHeight);
  expect(line, 'leading-tight must still beat the token’s baked 16px line').toBe(
    '13.75px',
  );
});
