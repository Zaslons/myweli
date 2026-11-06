import { expect, test, type Page } from '@playwright/test';

import { signInConsumer, signInPro } from './_auth';
import { asUnaskedBrowser } from './_push';
import { serveStubImages } from './_pixel';
import { priceRange } from '../../lib/format';

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
  /// Overrides the heading lookup when the heading is NOT proof the content
  /// rendered. `/mon-compte` is the case that forced this: its `<h1>Mon
  /// compte</h1>` lives in the SERVER page shell (`app/mon-compte/page.tsx:13`),
  /// outside `AccountClient` — which returns `SkeletonRows` while loading and
  /// `ErrorState` on failure. The heading survives both, so anchoring on it
  /// would let this subject scan a page with no tabs on it and report clean.
  /// That is the exact vacuity this file's own header memorialises about the
  /// 404 page, and the adversarial review caught B9 reintroducing it.
  ready?: (page: Page) => ReturnType<Page['getByRole']>;
  auth?: 'pro' | 'consumer';
  /// Reaches state the URL cannot. Strip #2 lives behind a « Liste » click:
  /// `RendezVousClient`'s default view is `journal`, so a test that merely
  /// loads the page never renders the tabs it is there to measure.
  setup?: (page: Page) => Promise<void>;
  /// Before the sign-in's first navigation — init scripts
  /// (`asUnaskedBrowser`, docs/design/web-pro-browser-push.md).
  init?: (page: Page) => Promise<void>;
  /// What the five generic checks cannot see on this route, asserted before
  /// them. They find what spills, what is cut off and what is truncated — never
  /// how many lines a string took, and never how far apart two controls ended
  /// up — because a layout that wraps is, to them, a layout that succeeded. A
  /// route whose risk is one of those two measures it here.
  measure?: (page: Page) => Promise<void>;
};

const PUBLIC_ROUTES: [name: string, url: string, anchor: string | RegExp][] = [
  ['the marketing home — all 15 of the h2s that grew 20 → 22px live here', '/', /Réservez beauté/],
  ['discovery', '/recherche?commune=Cocody', /Salons à Cocody/],
  // web-swiss-cards.md §8: every form a card can take, in a row. A long name wraps now,
  // so there is no declared loss left to protect this matrix from.
  ['discovery with every kind of card', '/recherche?q=vitrine', /Recherche : vitrine/],
  ['a root landing — the ruled index of cities', '/coiffure', /Coiffure en Côte d.Ivoire/],
  ['an area landing — one tile, chips and crumbs', '/coiffure/abidjan/cocody', 'Coiffure à Cocody'],
  ['an area landing with every kind of tile', '/coiffure/abidjan/marcory', 'Coiffure à Marcory'],
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
  // web-pro-access.md §4: the salons' page — the longest h1 on the public
  // site, two buttons side by side, six benefit cards.
  ['the not-found page', '/page-qui-nexiste-pas', 'Page introuvable'],
  ['the salons page — MyWeli Pro pour les salons', '/professionnels', /logiciel de réservation des salons/],
  // web-pro-access.md P4 — the Pro sign-up now has a header, and the consent.
  ['the pro sign-up — header + consent', '/pro/inscription', /Créer|compte/i],
  // B11: **this row runs before every authed row for a reason.** `signInPro`
  // drives this exact UI, so if the pro login breaks at 320 the authed half
  // fails at sign-in and every failure is misattributed to the page under test.
  // Measured here, first, where the failure names itself.
  ['the pro connexion — every authed row is standing on it', '/pro/connexion', 'Espace Pro'],
  // B11: the booking funnel — the product's most important consumer flow, and
  // this gate had never rendered it at any width. `axe.spec.ts` has scanned it
  // since B5; there was no reason but oversight for the overflow matrix not to.
  ['the booking funnel — the flow the whole product exists for', '/beaute-divine/reserver', /Réserver chez/],
];

/// **Text cut off the bottom of its own box** (B11 — 1.4.10's "without loss of
/// information" clause, the vertical half).
///
/// The predicate is `overflow-y: hidden|clip` **and** `scrollHeight >
/// clientHeight`, and the exclusions are the whole design:
///
/// - **`visible` is not a loss.** On the web an element with visible overflow
///   paints its excess *outside* the box. That can overlap, which is ugly, but
///   nothing is destroyed and the user can still read it. This is the one place
///   the web genuinely differs from mobile's twin
///   (`mobile/test/a11y/_a11y.dart:551`), where a Flutter box clips silently —
///   porting that predicate literally would have fired on every long page in
///   the product.
/// - **`auto`/`scroll` is not a loss either** — the content is reachable.
/// - **No text, no finding.** An `overflow-hidden` frame around an image is a
///   deliberate crop, and there are eleven of them; firing on those would bury
///   the one case that matters.
///
/// The warning behind all three is mobile's, and it was earned: *"a gate that
/// is red on correct behaviour gets deleted, and takes the true positives with
/// it."*
async function verticalClipping(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const bad: string[] = [];
    for (const el of Array.from(document.querySelectorAll<HTMLElement>('*'))) {
      if (!el.textContent?.trim()) continue;
      if (el.scrollHeight <= el.clientHeight + 1) continue; // cheap first
      // **The visually-hidden pattern is not a clip.** `sr-only` is a 1px box
      // with `overflow: hidden` around real text — that is how a skip link
      // reaches a screen reader without being seen, and it matched this
      // predicate on every single route (24 of 1). Keyed on the geometry rather
      // than the class name, because the pattern is universal and any
      // hand-rolled copy of it is equally correct.
      if (el.clientHeight <= 1 && el.clientWidth <= 1) continue;
      const o = getComputedStyle(el).overflowY;
      if (o !== 'hidden' && o !== 'clip') continue;
      bad.push(
        `<${el.tagName.toLowerCase()} class="${el.className}"> ` +
          `"${el.textContent.trim().slice(0, 40)}" ` +
          `needs ${el.scrollHeight} of ${el.clientHeight}`,
      );
    }
    return bad;
  });
}

/// **Text that is actually being truncated right now** (B11 — 1.4.10's "without
/// loss of information" clause, the horizontal half).
///
/// This is the hole `overflowingText` leaves open by design: it *skips*
/// `textOverflow: ellipsis` (`:95`), on the reasonable ground that an element
/// declaring truncation is not overflowing by accident. But a declared
/// truncation still removes information from the page, and 1.4.10 does not care
/// whether the removal was intentional.
///
/// **Two conditions, never one.** The class alone proves nothing: `truncate` on
/// a label whose content is short is correct and inert. The finding is
/// `textOverflow: ellipsis` **and** `scrollWidth > clientWidth` — text that is
/// being cut *at this viewport, with this data, right now*. Borrowed from
/// mobile's `expectNoLegibilityCrush` (`_a11y.dart:399`), which requires both
/// real truncation and being flexed: *"the question is not 'is this label
/// narrow' but 'did this label spend an ellipsis on a squeeze it did not
/// choose'."*
///
/// **What it cannot do:** decide whether the clipped string is the only copy of
/// that information. No machine can. That judgement is made once per site, by a
/// human, and written down as `// clip-ok:` — enforced by
/// `tests/tokens.theme-pin.test.ts`, which is the other half of this gate.
///
/// It is also blind to data it never sees: a name that fits with the stub's
/// « Awa » and clips with a real user's is invisible here. Named, not solved.
async function truncationLosses(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const bad: string[] = [];
    for (const el of Array.from(document.querySelectorAll<HTMLElement>('*'))) {
      if (!el.textContent?.trim()) continue;
      if (el.scrollWidth <= el.clientWidth + 1) continue; // cheap first
      if (getComputedStyle(el).textOverflow !== 'ellipsis') continue;
      bad.push(
        `<${el.tagName.toLowerCase()} class="${el.className}"> ` +
          `"${el.textContent.trim().slice(0, 40)}" ` +
          `cut at ${el.clientWidth} of ${el.scrollWidth}`,
      );
    }
    return bad;
  });
}

/// B11 — the reflow matrix (WCAG 1.4.10; WEB-SYSTEM §9 — Text scale & reflow).
///
/// **320 is the number the standard names**, and it is 55px narrower than
/// anything this suite had ever rendered. It is below every breakpoint
/// (`sm: 640px`), so it renders the *same* mobile-first layout as 375 with less
/// room — there is no new layout here, only an existing one under pressure.
///
/// The third entry is **deliberately beyond the SC**, and the distinction is
/// worth stating rather than blurring: 1.4.10 asks for 256 CSS px of height for
/// *horizontally* scrolling content, and these pages scroll vertically, so the
/// clause does not bind them. A short viewport is still where sticky and fixed
/// chrome fails, and it costs one array entry to find out.
const VIEWPORTS = [
  { name: '375×812', size: { width: 375, height: 812 } },
  { name: '320×512', size: { width: 320, height: 512 } },
  { name: '320×256', size: { width: 320, height: 256 } },
] as const;

/// The document must not scroll sideways. This is the blunt, honest check: if any
/// string got wide enough to push the layout, the body reports it here.
///
/// **B11 made it name the culprit.** It used to return a bare boolean, and its
/// two siblings both return a list of offenders — so the one assertion most
/// likely to fire on a new viewport was the one that said only *"the page
/// scrolls sideways"* about a document with several hundred elements. That is a
/// gate you cannot act on without re-deriving its finding by hand, which is how
/// a red run starts costing more than it saves.
///
/// It reports the elements that **start** the overflow: those whose own right
/// edge is past the viewport while their parent's is not. With `overflow:
/// visible` a parent's box does not stretch around a too-wide child, so the
/// child is the origin and the parent is innocent — walking down to the
/// outermost *overflowing* node would name the page shell every time.
///
/// The element walk only runs once the cheap document-level check has already
/// failed, so the cost is paid on failures and never on green runs — the
/// performance constraint `overflowingFlexRows` documents below is real.
async function horizontalOverflow(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const d = document.documentElement;
    // +1 for sub-pixel rounding; we are hunting real overflow, not 0.5px.
    const limit = d.clientWidth;
    if (d.scrollWidth <= limit + 1) return [] as string[];

    const past = (el: Element) => el.getBoundingClientRect().right > limit + 1;

    /// Inside a scroll/clip container, a wide box is **contained** — it is the
    /// declared 2D exception, not a document overflow. `getBoundingClientRect`
    /// reports the full untruncated box either way, so without this the journal
    /// grid (`min-w-fit`, 56 + 168 per artist) reads as a page-level failure on
    /// every pro route while the page it sits on is perfectly fine. Same opt-out
    /// the other two helpers grant, applied to ancestors instead of self.
    const contained = (el: Element) => {
      for (let p = el.parentElement; p; p = p.parentElement) {
        if (getComputedStyle(p).overflowX !== 'visible') return true;
      }
      return false;
    };

    const bad: string[] = [];
    for (const el of Array.from(document.querySelectorAll<HTMLElement>('*'))) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || !past(el)) continue;
      if (contained(el)) continue;
      if (el.parentElement && past(el.parentElement)) continue; // ancestor owns it
      bad.push(
        `<${el.tagName.toLowerCase()} class="${el.className}"> ` +
          `right ${Math.round(r.right)} > ${limit} (width ${Math.round(r.width)})`,
      );
    }
    // A document can be wider than its elements (a stray margin, a transform).
    // Say so rather than returning [] on a page that demonstrably scrolls.
    if (bad.length === 0) {
      bad.push(`the document is ${d.scrollWidth} wide in a ${limit} viewport, but no single element is past the edge`);
    }
    return bad;
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
///
/// **What it does NOT see**, named so a green run is not over-read (the
/// adversarial review's list):
/// - `need` sums ELEMENT children, so a bare text node — which becomes an
///   anonymous flex item with real width — is not counted. It under-reports.
/// - `inline-flex` passes the display filter but shrink-wraps its content, so
///   that half is inert unless a parent constrains it.
/// - `visibility: hidden` children still count; only `display: none` is skipped.
/// - It measures USED widths, so a row whose children legitimately shrink
///   (`min-w-0`, `truncate`) reads clean even when the text inside is clipped —
///   and `overflowingText` only walks text elements, so a clipped `<div>` or
///   `<li>` is invisible to both.
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
        // LAYOUT width, not painted width, for a transformed child: a
        // transform is paint-only and cannot make a flex row overflow, but
        // `getBoundingClientRect` measures the transformed box. The phone
        // field's country arrow is a 5px square turned 45° — 6.8px on screen,
        // 1px into an 8px padding, nothing clipped — and it read as « 2 items
        // need 40 of 38 » the first time /pro/inscription joined this matrix
        // (web-pro-access.md §11). An untransformed child keeps its exact
        // fractional rect.
        const width =
          cs.transform !== 'none' && child instanceof HTMLElement
            ? child.offsetWidth
            : child.getBoundingClientRect().width;
        const ml = parseFloat(cs.marginLeft) || 0;
        const mr = parseFloat(cs.marginRight) || 0;
        need += width + ml + mr;
        items += 1;
      }
      if (items < 2) continue; // a one-item row cannot be a strip
      const gap = (parseFloat(s.columnGap) || 0) * (items - 1);
      const pad = (parseFloat(s.paddingLeft) || 0) + (parseFloat(s.paddingRight) || 0);
      const have = el.clientWidth - pad;
      // A row that is not laid out cannot overflow. Extending this check to the
      // public routes surfaced `<div class="mt-m flex gap-s"> 2 items need 8 of
      // 0` on the salon page — a collapsed container whose children are both
      // 0-wide, so `need` was nothing but the gap. Reporting that would be the
      // start of teaching people to ignore this helper.
      if (have <= 0) continue;
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

type Box = { left: number; top: number; right: number; bottom: number };

/// How far apart two boxes are: the widest clear band between them on either
/// axis. Negative when they overlap.
function apart(a: Box, b: Box): number {
  return Math.max(
    a.left - b.right,
    b.left - a.right,
    a.top - b.bottom,
    b.top - a.bottom,
  );
}

/// SYSTEM.md §13.2: « Targets that are adjacent need ≥8px between them ».
const ADJACENT = 8;

/// Layout positions are multiples of 1/64px and no spacing token is under 4px,
/// so a tenth of a pixel absorbs rounding without excusing anything real.
const HAIR = 0.1;

/// The stub's Koffi (`sc1`, stored as `+2250700000001`) as the card prints it.
const CARD_NUMBER = '+225 07 00 00 00 01';

/// The Pro client card's phone row, **measured**
/// (docs/design/amounts-that-fit.md §11 Q3: « a phone number never wraps — the
/// actions drop below it instead »).
///
/// Three things, and each was a class name with nothing looking at the result:
///
/// 1. **The number is on one line.** With `flex-wrap` and `whitespace-nowrap`
///    both gone it broke over six lines at 320 — « +225 / 07 / 00 / 00 / 00 /
///    01 » — and every generic check below stayed empty.
/// 2. **A dropped action does not lie over the number.** « Appeler » and
///    « WhatsApp » are 48px boxes on a 24px line (`-my-sm`): each reaches 12px
///    above its own line, which is what the row's `gap-y-sm` is there to
///    absorb. Folded back into `gap-s`, the boxes start 4px inside the
///    number's line.
/// 3. **The dropped actions keep §13.2's 8px from « Nouveau rendez-vous »**,
///    which they now sit directly above. They reach 12px below their line as
///    well, and the button's block was `mt-m` (16px): 4px between the hit
///    areas at every phone width. It is `mt-l` now — 24 − 12 = 12px.
///
/// The number is found by **what it says**, as a text node, so this holds
/// whether or not it has an element of its own; if the stub's Koffi changes,
/// the first assertion says so rather than the rest passing about nothing.
/// The card's two longest values, on any day of the year.
///
/// The stub dates the last visit « today », so this page's overflow verdict was
/// a verdict on the calendar: green through October, red from 1 November, when
/// « novembre » stopped fitting a half-width tile at 320 (and it would have gone
/// green again in January, with nothing fixed). September is the longest month,
/// and seven figures is an amount a good salon reaches.
async function clientCardLongestValues(page: Page) {
  await page.route(/\/api\/pro\/clients\/sc1(\?|$)/, async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    const response = await route.fetch();
    const card = await response.json();
    await route.fulfill({
      response,
      json: {
        ...card,
        lastVisitAt: '2026-09-30T09:00:00.000Z',
        stats: { ...card.stats, spentFcfa: 1250000 },
      },
    });
  });
}

/// The tiles' shape, measured, because the text checks depend on the font: a
/// seven-figure amount fits a half-width tile at 320 on a Mac and not on CI's
/// wider Linux font. Two across at 375, one per row at 320, on any machine.
async function clientCardStatsShape(page: Page) {
  const width = page.viewportSize()?.width ?? 0;
  const xOf = async (label: string) =>
    (await page.getByText(label, { exact: true }).boundingBox())?.x;
  const [visits, spent] = [await xOf('Visites'), await xOf('Dépensé')];
  expect(visits, 'the « Visites » tile was not found').toBeDefined();
  if (width >= 360) {
    expect(spent, `two tiles across at ${width}px`).toBeGreaterThan(visits as number);
  } else {
    expect(spent, `one tile per row at ${width}px`).toBe(visits);
  }
}

async function clientCardPhoneRow(page: Page) {
  const at = `${page.viewportSize()?.width}px`;

  const number = await page.evaluate((shown) => {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let text: Node | null = null;
    while ((text = walker.nextNode())) {
      if ((text.nodeValue ?? '').trim() === shown) break;
    }
    if (!text) return null;
    const range = document.createRange();
    range.selectNodeContents(text);
    // One client rect per line box the text occupies.
    const lineTops = Array.from(
      new Set(Array.from(range.getClientRects(), (r) => Math.round(r.top))),
    );
    // The number's LINE is the box of the element that holds it and nothing
    // else (a flex item: its box is its line). A bare text node has no box of
    // its own, so its glyphs' box stands in.
    const holder = text.parentElement!;
    const b =
      holder.childNodes.length === 1
        ? holder.getBoundingClientRect()
        : range.getBoundingClientRect();
    return { lineTops, left: b.left, top: b.top, right: b.right, bottom: b.bottom };
  }, CARD_NUMBER);
  expect(
    number,
    `« ${CARD_NUMBER} » is not on the card — nothing below would be measured`,
  ).not.toBeNull();

  expect(
    number!.lineTops,
    `the phone number is broken over ${number!.lineTops.length} lines at ${at} — a number may not break (SYSTEM.md §13.3)`,
  ).toHaveLength(1);

  const targets: [name: string, box: Box][] = [];
  for (const [name, locator] of [
    ['Appeler', page.getByRole('link', { name: 'Appeler' })],
    ['WhatsApp', page.getByRole('link', { name: 'WhatsApp' })],
    ['Nouveau rendez-vous', page.getByRole('button', { name: 'Nouveau rendez-vous' })],
  ] as const) {
    const b = await locator.boundingBox();
    expect(b, `« ${name} » has no box at ${at}`).not.toBeNull();
    targets.push([
      name,
      { left: b!.x, top: b!.y, right: b!.x + b!.width, bottom: b!.y + b!.height },
    ]);
  }

  for (const [name, box] of targets.slice(0, 2)) {
    // Every viewport this file measures is too narrow for one line: the row
    // needs about 278px and the widest column here is 229px. An action still
    // beside the number means the two checks after this one measure nothing —
    // and « WhatsApp » dropping alone is how the row first broke at 375.
    expect(
      box.left < number!.right,
      `« ${name} » did not drop below the number at ${at} — the row is no longer the wrapped one this measures`,
    ).toBe(true);
    expect(
      box.top,
      `« ${name} » starts ${(number!.bottom - box.top).toFixed(1)}px inside the number's line at ${at}`,
    ).toBeGreaterThanOrEqual(number!.bottom - HAIR);
  }

  for (let i = 0; i < targets.length; i += 1) {
    for (let j = i + 1; j < targets.length; j += 1) {
      const [a, boxA] = targets[i];
      const [b, boxB] = targets[j];
      const gap = apart(boxA, boxB);
      expect(
        gap,
        `« ${a} » and « ${b} » are ${gap.toFixed(1)}px apart at ${at} — adjacent targets need ${ADJACENT}px (SYSTEM.md §13.2)`,
      ).toBeGreaterThanOrEqual(ADJACENT - HAIR);
    }
  }
}

/// One `describe` per viewport, and it is not a stylistic choice: `test.use` is
/// a **declaration**, legal at file scope or inside a `describe` callback and
/// nowhere else. Called from a bare `for` at file scope it re-declares the
/// file-level option — last write wins for the whole file — so the viewport
/// dimension cannot be a loop around `test()`. This is the shape the repo
/// already uses at `z-layers.spec.ts:35` and `booking.spec.ts:37`.
///
/// The file-level `test.use` above is deliberately kept: it is what the journal
/// line-height test at the bottom still runs under, unchanged.
for (const vp of VIEWPORTS) {
  test.describe(vp.name, () => {
    test.use({ viewport: vp.size });

    for (const [name, url, anchor] of PUBLIC_ROUTES) {
      test(`${name} — no overflow at ${vp.name}`, async ({ page }) => {
        await page.goto(url);
        // The content anchor is BOTH the "page rendered" signal AND the vacuity
        // guard — waiting on it beats `networkidle`, which never fires on the
        // image-bearing routes (the stub's salon photos point at an
        // unresolvable `cdn.stub`, so `next/image` keeps the network busy past
        // the 30s timeout; since B11.3 `_cdn-stub-dns.cjs` fails that lookup at once, so
        // it settles, and the anchor stays for the vacuity it guards). B8 found the salon route had been silently scanning
        // the 404 page for months (a slug rename left it 404, and the 404 page
        // doesn't overflow either — a green gate measuring nothing); a heading
        // unique to the REAL page makes that vacuity loud.
        // `.first()`: some routes carry a responsive heading twin (a visible h1
        // + an sr-only lg:hidden one); one is enough to prove the DOM is right.
        await expect(
          page.getByRole('heading', { name: anchor }).first(),
          `${url} did not render its own page (wrong DOM — vacuous scan)`,
        ).toBeVisible();
        expect(
          await horizontalOverflow(page),
          `the page scrolls sideways at ${vp.name}`,
        ).toEqual([]);
        expect(
          await overflowingText(page),
          `text spills out of its own box at ${vp.name}`,
        ).toEqual([]);
        // The third check belongs here too. B9 first wired it into the authed
        // loop only, which would have left the five public routes measured by
        // two of the three defect classes with nothing saying so.
        expect(
          await overflowingFlexRows(page),
          `a nowrap flex row does not fit its own container at ${vp.name}`,
        ).toEqual([]);
        // The two loss-of-information checks. They are the reason this file can
        // now call itself a 1.4.10 gate: the three above prove nothing SPILLS,
        // and these prove nothing was silenced to achieve that.
        expect(
          await verticalClipping(page),
          `text is cut off the bottom of its own box at ${vp.name}`,
        ).toEqual([]);
        expect(
          await truncationLosses(page),
          `text is being truncated away at ${vp.name}`,
        ).toEqual([]);
      });
    }
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
    // docs/design/web-pro-journal-panel-deposit.md — the « Journée » panel
    // opened on pj2 (pending, 5 000 FCFA deposit, screenshot): the acompte
    // line, the guidance sentence, the 144px thumbnail, « Voir le
    // rendez-vous », Accepter/Refuser. At 375 and 320 the panel IS the screen
    // (`w-full max-w-sm`), so this is where a long French sentence or a wide
    // screenshot would push it sideways.
    name: 'the journal panel — the deposit, its screenshot, the link',
    url: '/pro/rendez-vous',
    anchor: 'Rendez-vous',
    auth: 'pro',
    setup: async (page) => {
      await serveStubImages(page);
      await page.getByRole('button', { name: /Aminata/ }).click();
      // Vacuity guard: measured with the screenshot LOADED, not its skeleton
      // or its failure sentence.
      await expect(
        page.getByRole('button', { name: 'Agrandir le justificatif d’acompte' }),
      ).toBeVisible();
    },
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
    // docs/design/web-pro-week-strip.md — seven day buttons sharing the
    // width with no gap: at 320 each has ~41px for « Lun », the number and
    // the dot. `ready` is the vacuity guard — measured with the strip drawn.
    name: 'the pro agenda — the week strip above the Journée',
    url: '/pro/rendez-vous',
    anchor: 'Rendez-vous',
    auth: 'pro',
    ready: (page) => page.getByRole('group', { name: /^Semaine du / }),
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
    // docs/design/web-pro-deposit-app-rules.md — the app's explanations
    // (the longest: the cancellation sentence) and the delay choices.
    name: 'the pro deposit page — explanations and the delay choices',
    url: '/pro/acompte',
    anchor: 'Acompte',
    auth: 'pro',
    ready: (page) => page.getByRole('radiogroup', { name: 'Politique d’annulation' }),
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
    // The strip itself, not the shell's heading — see `ready` above.
    ready: (page) =>
      page.getByRole('group', { name: 'Filtrer mes rendez-vous' }),
  },
  // ---- B11 -----------------------------------------------------------------
  //
  // Six routes this file had never visited, added because the reflow gate's
  // loss-of-information half is **blind to a page it does not open**. Three of
  // the four sites where a truncated string is the ONLY copy of its information
  // — the team member's e-mail, the uploaded document's filename, the client
  // list — live here. Measuring `truncate` on routes that carry none of them is
  // how a gate reports clean about a defect it was written to find.
  //
  // Every one of them is already scanned by `axe.spec.ts`, with these same
  // helpers, so their reachability was never in question.
  {
    name: 'the pro dashboard — three stat tiles and a French label each',
    url: '/pro',
    anchor: /Aujourd’hui/,
    auth: 'pro',
  },
  {
    name: 'the pro roster — the e-mail column is the row’s only identity',
    url: '/pro/equipe',
    anchor: 'Équipe',
    auth: 'pro',
  },
  {
    name: 'the pro client list — names in a table that truncates',
    url: '/pro/clients',
    anchor: 'Clients',
    auth: 'pro',
  },
  {
    name: 'the pro KYC page — the uploaded filename appears nowhere else',
    url: '/pro/verification',
    anchor: 'Vérification',
    auth: 'pro',
  },
  {
    name: 'the consumer notification prefs — the switch row and its title bar',
    url: '/mon-compte/notifications',
    anchor: 'Notifications',
    auth: 'consumer',
  },
  {
    // The planning census called `AvisClient.tsx:108`'s `min-w-56` (224px) the
    // ONE uncontained hard floor in the product. Measured here rather than
    // argued: its parent `Card` is `flex flex-wrap`, so the list wraps onto its
    // own line and 224 fits the ~240 a 320 viewport leaves. The census read the
    // child and not the parent.
    name: 'the pro reviews — the 224px distribution list the census flagged',
    url: '/pro/avis',
    anchor: 'Avis',
    auth: 'pro',
  },
  {
    // The salon's notification center (web-pro-notifications.md §6): the
    // « Tout marquer comme lu » button beside the h1, and the reschedule
    // body — the longest sentence the server writes to a salon.
    name: 'the pro notification center',
    url: '/pro/notifications',
    anchor: 'Notifications',
    auth: 'pro',
  },
  {
    // docs/design/salon-email-alerts.md §4 — « Alertes par e-mail »: a long
    // sentence carrying the member's address (an unbreakable string) beside
    // the 48px switch. `ready` is the switch: measured with it drawn.
    name: 'the pro notification center — « Alertes par e-mail »',
    url: '/pro/notifications',
    anchor: 'Notifications',
    auth: 'pro',
    ready: (page) => page.getByRole('switch', { name: 'Alertes par e-mail' }),
  },
  {
    // docs/design/web-pro-browser-push.md §3 — « Notifications du
    // navigateur » above « Alertes par e-mail »: its long sentence beside the
    // 48px switch. `ready` is the switch.
    name: 'the pro notification center — « Notifications du navigateur »',
    init: asUnaskedBrowser,
    url: '/pro/notifications',
    anchor: 'Notifications',
    auth: 'pro',
    ready: (page) => page.getByRole('switch', { name: 'Notifications du navigateur' }),
  },
  {
    // §2 — the Accueil's band, its sentence and its two buttons.
    name: 'the pro home — the notifications band',
    init: asUnaskedBrowser,
    url: '/pro',
    anchor: 'Aujourd’hui',
    auth: 'pro',
    ready: (page) => page.getByRole('heading', { name: 'Activer les notifications' }),
  },
  // ---- amounts-that-fit (docs/design/amounts-that-fit.md §8.5) -------------
  {
    // The client CARD — the page behind every row of « the pro client list »
    // above, and until this entry in no matrix at all. **It was scrolling
    // sideways at all three viewports**, and this entry is what said so, run
    // against the card as it was: `<div class=""> right 379 > 375 (width
    // 355)`, and `379 > 320`. Its header row — the stored number, « Appeler »,
    // « WhatsApp » — was a `nowrap` flex row of three unbreakable items, so the
    // card could not be narrower than 355px. The row now wraps: the number
    // keeps its line and the two actions drop below it.
    //
    // `ready` is the phone row itself, not the `<h1>`: a card that rendered
    // without its phone row would be measured clean about the one thing this
    // entry is here for. « Appeler » exists only on the LOADED card of a client
    // who has a number (`sc1`, the stub's Koffi) — the error state and
    // « Client introuvable. » carry neither it nor the name.
    //
    // **What the five checks do NOT say, and `measure` does.** With BOTH
    // `flex-wrap` and `whitespace-nowrap` removed the number breaks over six
    // lines at 320 — « +225 / 07 / 00 / 00 / 00 / 01 » — and all five stay
    // empty, because wrapping is how a layout succeeds; they only see the
    // overflow that losing `flex-wrap` alone brings back. Before `measure` this
    // row would have stayed green about a number in six pieces: the rule was
    // held by two class assertions in jsdom. `clientCardPhoneRow` looks at the
    // rendered line, and at where the dropped actions landed.
    name: 'the pro client card — the grouped number and its two actions',
    url: '/pro/clients/sc1',
    anchor: /Koffi/,
    auth: 'pro',
    ready: (page) => page.getByRole('link', { name: 'Appeler' }),
    measure: clientCardPhoneRow,
  },
  {
    // Not the phone row: the stat tiles, with their longest values. `ready`
    // waits for the seven figures, so a route that stopped matching cannot
    // pass by measuring the stub's short ones.
    name: 'the pro client card — its stats at their longest',
    init: clientCardLongestValues,
    url: '/pro/clients/sc1',
    anchor: /Koffi/,
    auth: 'pro',
    ready: (page) => page.getByText(/1.250.000/),
    measure: clientCardStatsShape,
  },
];

for (const vp of VIEWPORTS) {
  test.describe(vp.name, () => {
    test.use({ viewport: vp.size });

    for (const route of AUTHED_ROUTES) {
      test(`${route.name} — no overflow at ${vp.name}`, async ({ page }) => {
        await route.init?.(page);
        if (route.auth === 'pro') await signInPro(page);
        else await signInConsumer(page);

        await page.goto(route.url);
        await expect(
          (route.ready?.(page) ??
            page.getByRole('heading', { name: route.anchor })).first(),
          `${route.url} did not render its own page (wrong DOM — vacuous scan)`,
        ).toBeVisible();
        await route.setup?.(page);

        // **The anchor alone is not enough, and the adversarial review proved
        // it.** Every authed client hands `ErrorState` its own page title, and
        // `ErrorState` renders that title as an `<h1>` (`ErrorState.tsx:31`) —
        // so a failed stub fetch produces a page whose heading matches the
        // anchor *exactly*, and all five assertions below then scan an error
        // page: one heading, one sentence, one button. Nothing overflows,
        // nothing clips, nothing truncates. **Green, about nothing.**
        //
        // That is the vacuity this file's own header memorialises about the 404
        // page, reintroduced on 11 of 12 authed rows — including all six added
        // because "the gate is blind to a page it does not open". `ready` was
        // the documented escape hatch and only `/mon-compte` used it.
        //
        // One structural check covers every row instead of eleven bespoke ones:
        // a page-level `ErrorState` always renders `<p role="alert">` carrying
        // its message, whatever its title.
        //
        // **The text filter is load-bearing, not tidiness.** Next.js renders
        // `<div id="__next-route-announcer__" role="alert">` on every page for
        // SPA navigation announcements — always present, empty on load. Keying
        // on the role alone reddened all 11 authed rows on framework chrome,
        // which is the "gate that is red on correct behaviour" failure this file
        // keeps warning about. An error state is an alert **with something to
        // say**.
        //
        // **And the announcer is excluded by its id, not by being empty.** It is
        // empty only until a client-side navigation — then it reads the new
        // page title aloud. Since the agenda keeps its view in the address
        // (web-pro-agenda-in-url.md), « Liste » IS such a navigation, and the
        // announcer saying « Pro — Rendez-vous · MyWeli » read as an error.
        expect(
          (await page.locator('[role="alert"]:not(#__next-route-announcer__)').allTextContents())
            .map((t) => t.trim())
            .filter(Boolean),
          `${route.url} rendered an error state — every assertion below would be vacuous`,
        ).toEqual([]);

        await route.measure?.(page);

        expect(
          await horizontalOverflow(page),
          `the page scrolls sideways at ${vp.name}`,
        ).toEqual([]);
        expect(
          await overflowingText(page),
          `text spills out of its own box at ${vp.name}`,
        ).toEqual([]);
        expect(
          await overflowingFlexRows(page),
          `a nowrap flex row does not fit its own container at ${vp.name}`,
        ).toEqual([]);
        // The two loss-of-information checks. They are the reason this file can
        // now call itself a 1.4.10 gate: the three above prove nothing SPILLS,
        // and these prove nothing was silenced to achieve that.
        expect(
          await verticalClipping(page),
          `text is cut off the bottom of its own box at ${vp.name}`,
        ).toEqual([]);
        expect(
          await truncationLosses(page),
          `text is being truncated away at ${vp.name}`,
        ).toEqual([]);
      });
    }
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

/// docs/design/web-pro-week-view.md — the « Semaine » tab exists from desktop
/// width only, so the phone matrix above cannot see it. At the narrowest
/// desktop (1024, the sidebar beside it) and a common one: the page never
/// scrolls sideways (the seven columns scroll inside their own box), and no
/// text spills from its box.
test.describe('the « Semaine » tab at desktop widths (web-pro-week-view)', () => {
  for (const width of [1024, 1280]) {
    test(`no overflow at ${width}`, async ({ page }) => {
      await page.setViewportSize({ width, height: 800 });
      await signInPro(page);
      await page.goto('/pro/rendez-vous?vue=semaine');
      await expect(page.getByRole('table', { name: /^Semaine du / })).toBeVisible();
      await expect(page.getByRole('button', { name: /— Sans artiste, Lun \d+ à 15:30$/ })).toBeVisible();
      expect(await horizontalOverflow(page), `the page scrolls sideways at ${width}`).toEqual([]);
      expect(await overflowingText(page), `text spills out of its own box at ${width}`).toEqual([]);
    });
  }
});

/// The salon page at doubled text (docs/design/web-salon-price-reflow.md).
///
/// Everything above renders text at its normal size, and that is how the salon
/// page shipped 441px wide at 200 % text on a 320 phone: the price was
/// `whitespace-nowrap`, and « 15 000 – 25 000 FCFA » at 32px could not fit
/// beside « Tresses ». A phone doubles text in two ways, and they fail
/// differently, so both run:
///
/// - **Android-style** (a touch phone, `text-size-adjust: 200%`): the browser
///   grows the LAYOUT viewport to hold the overflow — 441×783 on a 320×568
///   screen — so the fixed « Réserver » bar and the favourites toast are placed
///   off screen. `horizontalOverflow` measures against that grown viewport and
///   reads clean; the viewport's own size is the assertion that sees it.
/// - **The browser font at 200 %** (a 32px root): the viewport stays 320 and the
///   document scrolls sideways — `horizontalOverflow`'s case.
const DOUBLED_TEXT = [
  {
    name: 'Android-style doubled text',
    use: { isMobile: true, hasTouch: true, deviceScaleFactor: 2 },
    // `!important` because preflight pins `-webkit-text-size-adjust: 100%` on
    // `html`; this stands in for the phone's setting, which outranks the page.
    css: 'html { -webkit-text-size-adjust: 200% !important; text-size-adjust: 200% !important; }',
  },
  {
    name: 'the browser font at 200 %',
    use: {},
    // The preference sets the root size; nothing on the site sets its own.
    css: 'html { font-size: 32px; }',
  },
] as const;

/// The smallest phone screen 1.4.10 names, at a real phone's height.
const PHONE_320 = { width: 320, height: 568 };

/// « Services & tarifs », measured row by row: the service name's box, the
/// price's box, the row's, the price's computed font size, its line count, and
/// every token of the price that spans more than one line box.
///
/// **A token is what may not break** (amounts-that-fit.md §2): a number with
/// its grouping spaces, a word, the dash. The plain spaces between them are the
/// only legal breaks, so a token is a run between U+0020 — NOT `\s`, which in
/// JavaScript also matches the U+202F that groups « 250 000 », the same trap
/// that blinded mobile's `expectNoMidWordBreak`. Found in the price's text
/// nodes, so this holds whatever the price's markup becomes.
async function priceRows(page: Page) {
  return page
    .locator('section', { has: page.getByRole('heading', { name: 'Services & tarifs' }) })
    .locator('li')
    .evaluateAll((items) =>
      items.map((li) => {
        const name = li.querySelector<HTMLElement>(':scope > div > p')!;
        const price = li.querySelector<HTMLElement>(':scope > p')!;
        const box = (el: Element) => {
          const r = el.getBoundingClientRect();
          return { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
        };
        const whole = document.createRange();
        whole.selectNodeContents(price);
        const lines = new Set(Array.from(whole.getClientRects(), (r) => Math.round(r.top))).size;
        const broken: string[] = [];
        const walker = document.createTreeWalker(price, NodeFilter.SHOW_TEXT);
        for (let text = walker.nextNode(); text; text = walker.nextNode()) {
          for (const m of (text.nodeValue ?? '').matchAll(/[^ ]+/g)) {
            const range = document.createRange();
            range.setStart(text, m.index!);
            range.setEnd(text, m.index! + m[0].length);
            const lines = new Set(Array.from(range.getClientRects(), (r) => Math.round(r.top)));
            if (lines.size > 1) broken.push(m[0]);
          }
        }
        return {
          name: name.textContent ?? '',
          price: price.textContent ?? '',
          fontSize: parseFloat(getComputedStyle(price).fontSize),
          nameBox: box(name),
          priceBox: box(price),
          row: box(li),
          lines,
          broken,
        };
      }),
    );
}

/// **The stub's prices are too short to test the rule.** At 32px « 15 000 –
/// 25 000 » still fits one 288px line, so no number is ever asked to break, and
/// a price put back to `whitespace-nowrap` ends at x 317 — inside a 320 screen,
/// past its row, and invisible to every check. Both mutations passed this guard
/// until it measured a price that must wrap — and `break-all` passed even then,
/// cutting « F / CFA » rather than a number, until the check took words as
/// tokens too (see `priceRows`). So the second service is given the
/// longest range a salon here plausibly charges, written by the page's own
/// formatter; in the page rather than in the stub, whose prices other specs
/// count on.
const LONGEST_PRICE = priceRange(150000, 250000);

async function withLongestPrice(page: Page) {
  const shown = await page
    .locator('section', { has: page.getByRole('heading', { name: 'Services & tarifs' }) })
    .locator('li')
    .nth(1)
    .evaluate((li, text) => {
      const price = li.querySelector(':scope > p')!;
      price.textContent = text;
      return price.textContent;
    }, LONGEST_PRICE);
  expect(shown, 'the second service\'s price was not replaced').toBe(LONGEST_PRICE);
}

test.describe('the salon page at doubled text (web-salon-price-reflow)', () => {
  for (const mode of DOUBLED_TEXT) {
    test.describe(mode.name, () => {
      test.use({ viewport: PHONE_320, ...mode.use });

      test(`${mode.name} — the page keeps the screen's size at 320×568`, async ({ page }) => {
        await page.addInitScript((css) => {
          const add = () => {
            const style = document.createElement('style');
            style.textContent = css;
            document.head.appendChild(style);
          };
          if (document.head) add();
          else document.addEventListener('DOMContentLoaded', add);
        }, mode.css);
        await serveStubImages(page);
        await page.goto('/beaute-divine');
        await expect(
          page.getByRole('heading', { name: 'Beauté Divine' }).first(),
          '/beaute-divine did not render its own page (wrong DOM — vacuous scan)',
        ).toBeVisible();
        await withLongestPrice(page);

        const rows = await priceRows(page);
        expect(rows.length, 'fewer than two service rows — nothing below would be measured').toBeGreaterThanOrEqual(2);
        // The vacuity guard for the mode itself: a Chromium that ignored the
        // emulation would pass every check below at 16px.
        for (const row of rows) {
          expect(row.fontSize, `« ${row.price} » is not doubled — the mode did not apply`).toBe(32);
        }

        expect(
          await page.evaluate(() => [window.innerWidth, window.innerHeight]),
          'the layout viewport grew past the screen — fixed bars and toasts are placed off it',
        ).toEqual([PHONE_320.width, PHONE_320.height]);
        expect(await horizontalOverflow(page), 'the page scrolls sideways').toEqual([]);
        for (const row of rows) {
          expect(
            row.priceBox.right,
            `« ${row.price} » runs past its row's right edge`,
          ).toBeLessThanOrEqual(row.row.right + HAIR);
          expect(row.priceBox.left, `« ${row.price} » starts before its row`).toBeGreaterThanOrEqual(
            row.row.left - HAIR,
          );
        }
        expect(
          rows[1].lines,
          `« ${LONGEST_PRICE} » fits one line — the whole-token check below measures nothing`,
        ).toBeGreaterThan(1);
        for (const row of rows) {
          expect(
            row.broken,
            `« ${row.price} » breaks inside a token — a number or a word may not break (amounts-that-fit.md §2)`,
          ).toEqual([]);
        }
        expect(await overflowingText(page), 'text spills out of its own box').toEqual([]);
        expect(await overflowingFlexRows(page), 'a nowrap flex row does not fit its own container').toEqual([]);
        expect(await verticalClipping(page), 'text is cut off the bottom of its own box').toEqual([]);
        expect(await truncationLosses(page), 'text is being truncated away').toEqual([]);
      });
    });
  }

  /// The other half of the decision: at normal text the price never moves. It
  /// leaves its service's line only when the two cannot share one, which at
  /// 16px on the stub's services never happens — so a layout that always drops
  /// the price, or pulls it off the right edge, goes red here.
  for (const viewport of [PHONE_320, { width: 375, height: 812 }]) {
    test.describe(`normal text at ${viewport.width}`, () => {
      test.use({ viewport });

      test(`normal text — each price stays beside its service at ${viewport.width}`, async ({ page }) => {
        await serveStubImages(page);
        await page.goto('/beaute-divine');
        await expect(page.getByRole('heading', { name: 'Beauté Divine' }).first()).toBeVisible();
        await withLongestPrice(page);

        const rows = await priceRows(page);
        expect(rows.length, 'fewer than two service rows — nothing below would be measured').toBeGreaterThanOrEqual(2);
        for (const row of rows) {
          expect(row.fontSize, `« ${row.price} » is not at its normal size`).toBe(16);
          expect(
            row.priceBox.top,
            `« ${row.price} » left the line of « ${row.name} » at normal text`,
          ).toBeLessThan(row.nameBox.bottom);
          expect(
            Math.abs(row.priceBox.right - row.row.right),
            `« ${row.price} » is off the right edge of its row`,
          ).toBeLessThanOrEqual(HAIR);
        }
      });
    });
  }
});

/// The booking funnel at doubled text (docs/design/web-funnel-doubled-text.md).
///
/// The same failure as the salon page, in two rows the funnel repeats: a step
/// header (`SectionCard` — « Spécialiste » beside « Pas de préférence ») and a
/// recap row (`Recap` — a `dt` beside its `dd`). At 2× neither side has a word
/// short enough to give, so the row ran off its card and, at 320, the page grew
/// to 344×611 — taking the fixed « Confirmer » bar off the screen. And
/// « Confirmation » was one word wider than its card. The rule is the salon
/// page's: a value that cannot sit beside its label moves under it, on the
/// right edge.

/// Every label/value row the funnel draws: the step headers (a button that
/// opens its step, the title and the current choice) and the recap rows. For
/// each: both boxes, the row's, and every token of either side that spans two
/// line boxes — a token is a run between plain spaces (see `priceRows`), so a
/// date, a time, a price or a salon's name broken mid-word reads here.
async function funnelRows(page: Page) {
  return page.evaluate(() => {
    const rows = [
      ...Array.from(document.querySelectorAll<HTMLElement>('section > button[aria-expanded]')),
      ...Array.from(document.querySelectorAll<HTMLElement>('dl > div')),
    ].filter((row) => row.children.length === 2);
    const box = (el: Element) => {
      const r = el.getBoundingClientRect();
      return { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
    };
    const brokenTokens = (el: Element) => {
      const broken: string[] = [];
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
      for (let text = walker.nextNode(); text; text = walker.nextNode()) {
        for (const m of (text.nodeValue ?? '').matchAll(/[^ ]+/g)) {
          const range = document.createRange();
          range.setStart(text, m.index!);
          range.setEnd(text, m.index! + m[0].length);
          if (new Set(Array.from(range.getClientRects(), (r) => Math.round(r.top))).size > 1) {
            broken.push(m[0]);
          }
        }
      }
      return broken;
    };
    return rows.map((row) => {
      const [label, value] = Array.from(row.children);
      return {
        kind: row.tagName === 'BUTTON' ? ('step' as const) : ('recap' as const),
        label: label.textContent?.trim() ?? '',
        value: value.textContent?.trim() ?? '',
        labelFont: parseFloat(getComputedStyle(label).fontSize),
        labelBox: box(label),
        valueBox: box(value),
        row: box(row),
        broken: [...brokenTokens(label), ...brokenTokens(value)],
      };
    });
  });
}

/// The funnel, walked as `booking.spec.ts` walks it — a service, « Pas de
/// préférence », the first slot, « Confirmer », the code — calling `at` with
/// every step's rows in view.
///
/// **Clicks go through the DOM, and that is a recorded cost, not a shortcut.**
/// At doubled text the fixed bar covers 34–57 % of the screen
/// (web-funnel-doubled-text.md §6), so a pointer click on a control the page
/// scrolled to lands on the bar. The bar's shape is the open follow-up; this
/// file measures layout, and a pointer that cannot reach is not a layout fact.
async function walkFunnel(page: Page, at: (step: string) => Promise<void>) {
  const tap = (locator: ReturnType<Page['getByRole']>) =>
    locator.evaluate((el) => (el as HTMLElement).click());
  await page.goto('/beaute-divine/reserver');
  await expect(page.getByRole('heading', { level: 1, name: /Réserver chez Beauté Divine/ })).toBeVisible();
  await at('the steps, nothing chosen');
  await tap(page.getByRole('checkbox').first());
  await tap(page.getByRole('radio', { name: /Pas de préférence/ }));
  await tap(page.getByRole('button', { name: /^\d{2}:\d{2}$/ }).first());
  await expect(page.getByRole('button', { name: /^Date et heure/ })).toContainText(':');
  await at('the steps, a service, a specialist and a time chosen');
  await tap(page.getByRole('button', { name: 'Confirmer', exact: true }).last());
  await page.getByLabel('Votre e-mail').fill('awa@example.com');
  await tap(page.getByRole('button', { name: 'Continuer avec e-mail' }));
  await page.getByLabel('Code à 6 chiffres').fill('123456');
  await tap(page.getByRole('button', { name: 'Se connecter' }));
  await expect(page.getByRole('button', { name: 'Confirmer la réservation' })).toBeVisible();
  await at('the confirm step');
}

/// The double-unit total « 15 000 FCFA – 25 000 FCFA » that the bar, the side
/// panel and the recap printed (amounts-that-fit.md §2: a range prints its unit
/// once). Nothing else pins it.
const DOUBLE_UNIT = /FCFA\s–/;

/// The share of the screen the pinned bar may take (web-funnel-bar-fit.md §2):
/// above it, the bar sheds its total and keeps « Confirmer ».
const BAR_LIMIT = 0.25;

/// The funnel's pinned bar, measured (web-funnel-bar-fit.md).
///
/// Found from what it does rather than how it is styled: the visible
/// « Confirmer », then its first `sticky` or `fixed` ancestor. Reports the bar's
/// share of the screen, whether a total is shown visibly in the bar or in the
/// summary panel, and — after scrolling to the end of the page, then back —
/// how many px of the footer's last link and of the last step card sit under
/// it. The scroll is restored, so the walk continues where it was.
async function pinnedBar(page: Page) {
  return page.evaluate(() => {
    const confirm = Array.from(document.querySelectorAll('button')).find(
      (b) => b.textContent?.trim() === 'Confirmer' && b.checkVisibility(),
    );
    let bar: HTMLElement | null = confirm ?? null;
    while (bar && !['sticky', 'fixed'].includes(getComputedStyle(bar).position)) bar = bar.parentElement;
    if (!bar) return null;
    const isTotal = (el: Element) => /^\d[\d\s]*( – \d[\d\s]*)? FCFA$/.test(el.textContent?.trim() ?? '');
    const shown = (el: Element) => el.checkVisibility() && el.getBoundingClientRect().height > 0;
    const inBar = Array.from(bar.querySelectorAll('*')).some((el) => isTotal(el) && shown(el));
    const summary = bar.parentElement?.querySelector('aside');
    const inSummary = !!summary && Array.from(summary.querySelectorAll('*')).some((el) => isTotal(el) && shown(el));
    const share = bar.getBoundingClientRect().height / window.innerHeight;

    const y = window.scrollY;
    window.scrollTo(0, document.documentElement.scrollHeight);
    const b = bar.getBoundingClientRect();
    const under = (el: Element | null | undefined) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return Math.max(0, Math.min(r.bottom, b.bottom) - Math.max(r.top, b.top));
    };
    const links = document.querySelectorAll('footer a');
    const cards = Array.from(document.querySelectorAll('section')).filter((s) => s.querySelector(':scope > button[aria-expanded]'));
    const ends = { footerLink: under(links[links.length - 1]), lastCard: under(cards[cards.length - 1]) };
    window.scrollTo(0, y);
    return { share, inBar, inSummary, ...ends };
  });
}

/// The bar's checks, at every step that has one (the confirm step does not).
async function expectBarFits(page: Page, step: string, normalText: boolean) {
  const bar = await pinnedBar(page);
  expect(bar, `${step}: no pinned bar holds the visible « Confirmer »`).not.toBeNull();
  expect(bar!.share, `${step}: the bar takes ${Math.round(bar!.share * 100)} % of the screen`).toBeLessThanOrEqual(BAR_LIMIT);
  expect(bar!.inBar || bar!.inSummary, `${step}: no total is shown, in the bar or in the summary`).toBe(true);
  expect(bar!.footerLink, `${step}: at the page's end the footer's last link is under the bar`).toBe(0);
  expect(bar!.lastCard, `${step}: at the page's end the last step is under the bar`).toBe(0);
  if (normalText) expect(bar!.inBar, `${step}: at normal text the bar carries the total`).toBe(true);
}

test.describe('the booking funnel at doubled text (web-funnel-doubled-text)', () => {
  for (const mode of DOUBLED_TEXT) {
    test.describe(mode.name, () => {
      test.use({ viewport: PHONE_320, ...mode.use });

      test(`${mode.name} — every step keeps the screen's size at 320×568`, async ({ page }) => {
        await page.addInitScript((css) => {
          const add = () => {
            const style = document.createElement('style');
            style.textContent = css;
            document.head.appendChild(style);
          };
          if (document.head) add();
          else document.addEventListener('DOMContentLoaded', add);
        }, mode.css);
        await serveStubImages(page);

        await walkFunnel(page, async (step) => {
          const rows = await funnelRows(page);
          expect(rows.length, `${step}: no label/value rows — nothing would be measured`).toBeGreaterThanOrEqual(3);
          const headers = rows.filter((row) => row.kind === 'step');
          for (const row of headers) {
            expect(row.labelFont, `${step}: « ${row.label} » is not doubled — the mode did not apply`).toBe(32);
          }
          // The confirm step has no step titles, and it is where Chromium's
          // text autosizer — which implements `text-size-adjust` — was seen to
          // drop the doubling after the DOM changed. Its recap labels are the
          // 14px `bodyMedium`: doubled by the Android mode, untouched by a
          // larger root, whose px tokens do not follow it.
          const salon = rows.find((row) => row.kind === 'recap' && row.label === 'Salon');
          if (salon) {
            expect(salon.labelFont, `${step}: the recap is not at this mode's size`).toBe(
              'isMobile' in mode.use ? 28 : 14,
            );
          }
          expect(headers.length + (salon ? 1 : 0), `${step}: nothing proves the mode applied here`).toBeGreaterThan(0);
          expect(
            await page.evaluate(() => [window.innerWidth, window.innerHeight]),
            `${step}: the layout viewport grew past the screen — the bar is placed off it`,
          ).toEqual([PHONE_320.width, PHONE_320.height]);
          expect(await horizontalOverflow(page), `${step}: the page scrolls sideways`).toEqual([]);
          for (const row of rows) {
            for (const [side, b] of [['label', row.labelBox], ['value', row.valueBox]] as const) {
              expect(b.right, `${step}: « ${row.label} »'s ${side} runs past its row`).toBeLessThanOrEqual(row.row.right + HAIR);
              expect(b.left, `${step}: « ${row.label} »'s ${side} starts before its row`).toBeGreaterThanOrEqual(row.row.left - HAIR);
            }
            expect(row.broken, `${step}: « ${row.label} · ${row.value} » breaks inside a word`).toEqual([]);
          }
          expect(await overflowingText(page), `${step}: text spills out of its own box`).toEqual([]);
          expect(await overflowingFlexRows(page), `${step}: a nowrap flex row does not fit its own container`).toEqual([]);
          expect(await verticalClipping(page), `${step}: text is cut off the bottom of its own box`).toEqual([]);
          expect(await truncationLosses(page), `${step}: text is being truncated away`).toEqual([]);
          expect(
            await page.getByText(DOUBLE_UNIT).count(),
            `${step}: a total prints « FCFA » twice`,
          ).toBe(0);
          if (step !== 'the confirm step') await expectBarFits(page, step, false);
        });
        await expect(page.getByRole('heading', { level: 2, name: 'Confirmer' })).toBeVisible();
      });
    });
  }

  /// The other half: at normal text no value moves. Each sits on its label's
  /// line, at the row's right edge — the date card at 320 included, whose value
  /// wraps beside its title rather than under it.
  for (const viewport of [PHONE_320, { width: 375, height: 812 }]) {
    test.describe(`normal text at ${viewport.width}`, () => {
      test.use({ viewport });

      test(`normal text — every value stays beside its label at ${viewport.width}`, async ({ page }) => {
        await serveStubImages(page);
        await walkFunnel(page, async (step) => {
          const rows = await funnelRows(page);
          expect(rows.length, `${step}: no label/value rows — nothing would be measured`).toBeGreaterThanOrEqual(3);
          for (const row of rows) {
            expect(row.valueBox.top, `${step}: « ${row.value} » left the line of « ${row.label} »`).toBeLessThan(row.labelBox.bottom);
            expect(
              Math.abs(row.valueBox.right - row.row.right),
              `${step}: « ${row.value} » is off the right edge of its row`,
            ).toBeLessThanOrEqual(HAIR);
          }
          expect(await page.getByText(DOUBLE_UNIT).count(), `${step}: a total prints « FCFA » twice`).toBe(0);
          if (step !== 'the confirm step') await expectBarFits(page, step, true);
        });
        await expect(page.getByText(priceRange(15000, 25000), { exact: true }).first()).toBeAttached();
      });
    });
  }
});
