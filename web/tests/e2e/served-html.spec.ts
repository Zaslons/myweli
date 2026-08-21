import { expect, test } from '@playwright/test';

/// **What a crawler, a slow phone, and `curl` actually receive.**
///
/// Every other e2e file drives a JS-enabled Chromium and therefore observes the
/// HYDRATED page. That is why a 404 which serves 44 characters of visible text
/// has been green in `provider.spec.ts`, `landing.spec.ts`, `service.spec.ts`
/// and `redirects.spec.ts` — all four assert the 404 *routing*, and all four see
/// the page after ~232 KB of JS has arrived and run.
///
/// These use `request`, which performs no JS. It is the only view in the suite
/// that matches what is on the wire.

test('the sitemap lists the commune level, not only roots and cities', async ({ request }) => {
  // Until 2026-08-20 the third level came from `getLandingParams`, which lists
  // "combos present in the catalogue". With an empty catalogue that silently
  // dropped ~187 live, indexable, 200-answering pages from the sitemap.
  const xml = await (await request.get('/sitemap.xml')).text();
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  const threeLevel = locs.filter((u) => new URL(u).pathname.split('/').filter(Boolean).length === 3);
  expect(
    threeLevel.length,
    'the commune level is derived from the locality tree, so it does not '
      + 'disappear when the catalogue is empty',
  ).toBeGreaterThan(0);

  // And every listed URL must actually answer — a sitemap of 404s is worse
  // than a short one.
  //
  // **200 alone does not test the claim being made.** The sitemap asserts these
  // are INDEXABLE pages; a `noindex` page answers 200 exactly like an
  // indexable one, so the old status-only check could not tell the difference
  // between a sitemap of real landing pages and a sitemap of pages telling
  // crawlers to go away. `/[slug]/reserver` is a live example of a 200 that
  // must never appear here.
  for (const u of threeLevel.slice(0, 5)) {
    const res = await request.get(new URL(u).pathname);
    expect(res.status(), `${u} is listed but does not answer`).toBe(200);
    const html = await res.text();
    expect(
      /<meta[^>]+name="robots"[^>]+noindex/i.test(html),
      `${u} is in the sitemap but tells crawlers not to index it`,
    ).toBe(false);
  }
});

test('every sitemap entry carries a <lastmod>', async ({ request }) => {
  // One document-level timestamp, not a per-URL invention: nothing in this
  // system records when an individual landing page last changed, and a fake
  // per-URL date is a claim a crawler acts on.
  const xml = await (await request.get('/sitemap.xml')).text();
  const locs = [...xml.matchAll(/<loc>/g)].length;
  const mods = [...xml.matchAll(/<lastmod>/g)].length;
  expect(locs).toBeGreaterThan(0);
  expect(mods, 'every <url> needs a <lastmod>, not just some').toBe(locs);
});

test('the sitemap has no duplicate <loc>', async ({ request }) => {
  const xml = await (await request.get('/sitemap.xml')).text();
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  expect(locs.length - new Set(locs).size, 'duplicate <loc> entries').toBe(0);
});

test('the sign-in slot is reserved in the SERVED html', async ({ request }) => {
  // `/connexion` wrapped its client component in a bare `<Suspense>` — no
  // fallback means React renders NOTHING there, so the server streamed an empty
  // hole and the form dropped into it on hydration. Production measured CLS
  // 0.131 against a 0.1 budget, on every run, under mobile/3G.
  //
  // Asserted on the SERVED html because that is where the hole was: with JS on,
  // every existing e2e sees the hydrated form and cannot tell the difference.
  for (const path of ['/connexion', '/pro/connexion']) {
    const html = await (await request.get(path)).text();
    expect(
      html,
      `${path} streams an empty Suspense slot — the form will drop in and shift `
        + 'the page',
    ).toContain('auth-form-skeleton');
  }
});

/// **The 404 on the wire — fixed 2026-08-21, and this is how.**
///
/// `notFound()` called from a route that MATCHED used to make Next serve
/// `<html id="__next_error__">` with 44 characters of visible text: the real UI
/// existed only in the RSC payload, so a visitor on a slow connection saw a
/// blank white page until ~232 KB of JS landed. A route matching NOTHING served
/// the prerendered page correctly. That contrast was the whole diagnosis, and
/// the mechanism is now measured rather than guessed:
///
///   PRERENDERED notFound()  -> the real 404, 311 visible characters
///   REQUEST-TIME notFound() -> the __next_error__ shell, 44 characters
///
/// and request-time is unavoidable once the params are open. Ruled out by
/// measurement, not assumption: a framework upgrade (identical on 14.2.35,
/// 15.5.23 and 16.3.1), a `not-found.tsx` colocated in `app/[slug]/` (its
/// marker reaches the RSC payload and nothing else), `force-dynamic`
/// (`/[slug]/reserver` already had it and still shelled), and a segment
/// `layout.tsx` carrying the bound (does not gate a dynamically-rendered
/// child).
///
/// **The fix is `dynamicParams = false`** on the three routes whose valid space
/// is finite and known at build time, so an unknown param never enters the
/// route and takes the already-working unmatched path. `/[slug]/reserver` reads
/// `searchParams`, which forces a per-request render and defeats the bound, so
/// it hands its 404 one segment up instead — giving up `searchParams` there
/// would have cost the funnel its server-rendered service list, which is the
/// content this whole item exists to protect.
///
/// The assertion must strip `<script>` first. « Page introuvable » IS present
/// in the raw bytes of the broken version — inside the RSC flight payload — so
/// a plain `toContain` passes while the visitor sees a blank page. The first
/// version of this test did exactly that and reported the defect as fixed.
function visibleText(html: string): string {
  const stripped = html
    .replace(/<script[\s\S]*?<\/script>/g, '')
    .replace(/<style[\s\S]*?<\/style>/g, '')
    .replace(/<[^>]+>/g, ' ');
  return stripped.replace(/\s+/g, ' ').trim();
}

/// Every `notFound()` call site in the app, plus the control. `/[slug]/reserver`
/// was never in any test before this — the one cell nobody had measured.
const NOT_FOUND_PATHS = [
  ['a route matching nothing (CONTROL)', '/a/b/c/d/e'],
  ['[slug] — an unknown slug', '/this-does-not-exist'],
  ['[slug] — a suspended salon', '/salon-arrete'],
  ['[slug]/[city]', '/coiffure/nowhere'],
  ['[slug]/[city]/[area]', '/coiffure/abidjan/nowhere'],
  ['[slug]/reserver', '/unknown-salon/reserver'],
] as const;

for (const [label, path] of NOT_FOUND_PATHS) {
  test(`404 in the SERVED html: ${label}`, async ({ request }) => {
    const res = await request.get(path);
    expect(res.status(), `${path} must still be a 404`).toBe(404);
    const text = visibleText(await res.text());
    expect(
      text,
      `${path} served ${text.length} visible characters — a blank page until the JS lands`,
    ).toContain('Page introuvable');
  });
}

test('the booking funnel keeps its server-rendered content', async ({ request }) => {
  // The reason `/[slug]/reserver` defers its 404 instead of dropping
  // `searchParams`: this list is what a slow phone reads before any JS runs,
  // and a Suspense boundary would replace all of it with a skeleton.
  const text = visibleText(await (await request.get('/beaute-divine/reserver')).text());
  expect(text).toContain('Tresses');
  expect(text).toContain('Soin visage');
});

test('the legacy flat landing still redirects rather than 404ing', async ({ request }) => {
  // Closing `dynamicParams` blocks any slug `generateStaticParams` did not
  // list, and the legacy flat slugs 308 from inside `[slug]/page.tsx`. Leaving
  // them out turned every one of those redirects into a 404 — measured, and
  // the reason `legacyFlatSlugs` exists.
  const res = await request.get('/coiffure-cocody', { maxRedirects: 0 });
  expect(res.status(), 'a 404 here is a silent SEO regression').toBe(308);
});
