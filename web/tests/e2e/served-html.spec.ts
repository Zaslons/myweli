import { expect, test } from '@playwright/test';
import { taxonomyRootSlugs } from '../../lib/taxonomy';

/// The stub the suite runs against, so the oracle below is derived from the
/// same tree the app reads rather than from a number written down here.
const STUB = 'http://127.0.0.1:8787';

type LocalityCountry = {
  cities?: { areas?: unknown[] }[];
};

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

  // **`> 0` could not fail on the defect it was written for.** The old source,
  // `getLandingParams`, lists "combos present in the catalogue" — which is
  // ZERO in production, where no salon exists, and NON-ZERO here, where the
  // stub has one. So reverting the derivation would have kept this green in
  // CI while silently dropping ~187 pages from the live sitemap: the guard
  // passed on the stub for the same reason the bug hid in production.
  //
  // The oracle has to be the derivation itself. Every taxonomy root × every
  // commune in the tree, exactly — no more (a duplicate or a stale catalogue
  // entry) and no fewer (a dropped loop, or a partial revert).
  const tree = await (await request.get(`${STUB}/localities`)).json();
  const communes = (tree.countries ?? []).flatMap((c: LocalityCountry) =>
    (c.cities ?? []).flatMap((city) => city.areas ?? []),
  ).length;
  const expected = taxonomyRootSlugs().length * communes;
  expect(communes, 'the stub served no communes — the oracle is vacuous').toBeGreaterThan(0);
  expect(
    threeLevel.length,
    `expected ${taxonomyRootSlugs().length} roots x ${communes} communes = `
      + `${expected} commune URLs; the sitemap has ${threeLevel.length}`,
  ).toBe(expected);

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

/// **The `[slug]/reserver` row above measures the wrong thing on its own.**
/// `request.get()` follows redirects by default, so it silently walks the 307
/// to `/{slug}` and asserts on THAT page — the row labelled "the one cell nobody
/// had measured" was re-measuring the cell beside it. The hop itself needs
/// pinning, or retargeting the redirect at any other 404-ing path keeps it
/// green.
test('[slug]/reserver hands its 404 one segment up, and that is the hop', async ({
  request,
}) => {
  const res = await request.get('/unknown-salon/reserver', { maxRedirects: 0 });
  expect(res.status(), 'a 307 is the mechanism; a 404 here means it changed').toBe(307);
  expect(
    res.headers()['location'],
    'the redirect must land on /[slug], whose params ARE closed',
  ).toBe('/unknown-salon');
});

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

/// **An offer a visitor cannot take.** `OpenInAppButton` and `AppInstallBanner`
/// each correctly render no LINK while the apps are unlisted — but the copy
/// around them stayed, so production served « L'app MyWeli — Réservez plus vite
/// et gérez vos rendez-vous depuis votre poche. » with no store link anywhere in
/// the document (measured 2026-08-21).
///
/// `open-in-app.test.tsx` could not see it: it renders the button in isolation
/// and passes, because the orphan is the WRAPPER.
///
/// Written as an INVARIANT rather than "the section is absent", so it keeps
/// working the day the apps are listed: promise and link appear together or not
/// at all. Both directions can fail — copy without a link is today's defect, and
/// a link with no copy would be a bare button nobody can interpret.
/// **Every page that could carry the promise, not just the homepage.** The
/// first version visited `/` only — and the identical defect was live on
/// `/pro/connexion` (« Créez votre salon dans l'app MyWeli Pro. » with no store
/// link) for as long as this guard existed, because the invariant was stated
/// site-wide in the docstring and enforced on one URL. That is the same shape
/// as the privacy allowlist that watched three routes and missed the fourth.
for (const path of ['/', '/connexion', '/pro/connexion', '/recherche?q=tresses']) {
test(`the app is promised only where it can actually be got: ${path}`, async ({ page }) => {
  await page.goto(path);
  await page.waitForLoadState('networkidle');

  const body = (await page.locator('body').innerText()).toLowerCase();
  const promises = ["l’app myweli", "l'app myweli", 'téléchargez l’app', "téléchargez l'app"];
  const promised = promises.some((p) => body.includes(p));

  const links = await page
    .locator('a[href*="apps.apple.com"], a[href*="play.google.com"]')
    .count();

  expect(
    promised === links > 0,
    promised
      ? `${path} offers the app and gives no way to install it`
      : `${path} has a store link but nothing telling anyone what it is`,
  ).toBe(true);
});
}

/// **The flags must actually be there, not merely same-origin.**
///
/// `#476` moved the phone-field flags off GitHub Pages by copying them into
/// `public/flags/` from a `prebuild` step. Delete that step and the guards all
/// stay green: the request becomes `myweli.com/flags/CI.svg`, which is not a
/// foreign host, so the third-party allowlist — the guard written for exactly
/// this defect — is structurally blind to it. The visitor gets a broken image
/// and the privacy fix silently reverts to nothing.
///
/// So the assertion is that the file is SERVED, not that the URL is ours.
test('the self-hosted flags are actually served', async ({ request }) => {
  const res = await request.get('/flags/CI.svg');
  expect(res.status(), '/flags/CI.svg is missing — has the prebuild step run?').toBe(200);
  expect(res.headers()['content-type']).toContain('svg');

  // The control: the origin is not blanket-200ing, so the check above means
  // the file exists rather than that everything under /flags/ answers.
  expect((await request.get('/flags/ZZZ.svg')).status()).toBe(404);
});

/// And the page that uses them points at ours.
test('the phone field asks OUR origin for its flag', async ({ page }) => {
  const flagRequests: string[] = [];
  page.on('request', (r) => {
    if (/\.svg(\?|$)/.test(r.url()) && /flag/i.test(r.url())) flagRequests.push(r.url());
  });
  const res = await page.goto('/pro/inscription');
  await page.waitForLoadState('networkidle');
  expect(res?.status()).toBe(200);

  // The page must really render a phone field, or this passes vacuously — the
  // exact trap the privacy allowlist fell into with a /mon-compte entry that
  // redirects to /connexion and renders no phone field at all.
  await expect(page.locator('img[src*="/flags/"]').first()).toBeVisible();
  for (const u of flagRequests) {
    expect(new URL(u).hostname, 'a flag came from somewhere else').toBe('127.0.0.1');
  }
});

/// **The headers as a browser receives them.** `next.config.mjs` can be right in
/// source and absent from the response for a dozen reasons — a `headers()` that
/// throws, a `source` pattern that misses, a route served by the routing layer
/// before the page. This file's whole purpose is what is actually on the wire.
test('the security headers are on the response', async ({ request }) => {
  const h = (await request.get('/')).headers();

  expect(h['x-frame-options']).toBe('DENY');
  expect(h['x-content-type-options']).toBe('nosniff');
  expect(h['referrer-policy']).toBe('strict-origin-when-cross-origin');

  const csp = h['content-security-policy-report-only'];
  expect(csp, 'no CSP at all — headers() is not reaching the response').toBeTruthy();
  // Report-Only, deliberately, until real violations say enforcing is safe.
  expect(h['content-security-policy'], 'enforcing before the reports were read').toBeUndefined();

  // Spot-check the three whose omission breaks production silently, so this
  // fails on a policy that shipped without them rather than only on no policy.
  expect(csp).toContain('worker-src blob:');
  expect(csp).toContain('*.cartocdn.com');
  expect(csp).toContain('*.r2.cloudflarestorage.com');
  expect(csp).toContain("frame-ancestors 'none'");
});

test('the headers are on a 404 too, not only on pages that succeed', async ({ request }) => {
  // A `source: '/:path*'` rule is easy to get subtly wrong, and an error page
  // is exactly where clickjacking protection still matters.
  const h = (await request.get('/this-does-not-exist')).headers();
  expect(h['x-frame-options']).toBe('DENY');
  expect(h['content-security-policy-report-only']).toBeTruthy();
});
