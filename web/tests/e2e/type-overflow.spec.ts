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
      if (el.clientHeight <= 1 || el.clientWidth <= 1) continue;
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
/// `tests/truncation.pin.test.ts`, which is the other half of this gate.
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

/// B11 — the reflow matrix (WCAG 1.4.10; WEB-SYSTEM §9.4).
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
        // the 30s timeout). B8 found the salon route had been silently scanning
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
    // The strip itself, not the shell's heading — see `ready` above.
    ready: (page) =>
      page.getByRole('group', { name: 'Filtrer mes rendez-vous' }),
  },
  // ---- B11 -----------------------------------------------------------------
  //
  // Five routes this file had never visited, added because the reflow gate's
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
];

for (const vp of VIEWPORTS) {
  test.describe(vp.name, () => {
    test.use({ viewport: vp.size });

    for (const route of AUTHED_ROUTES) {
      test(`${route.name} — no overflow at ${vp.name}`, async ({ page }) => {
        if (route.auth === 'pro') await signInPro(page);
        else await signInConsumer(page);

        await page.goto(route.url);
        await expect(
          (route.ready?.(page) ??
            page.getByRole('heading', { name: route.anchor })).first(),
          `${route.url} did not render its own page (wrong DOM — vacuous scan)`,
        ).toBeVisible();
        await route.setup?.(page);

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
