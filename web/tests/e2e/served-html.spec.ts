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
  for (const u of threeLevel.slice(0, 5)) {
    expect((await request.get(new URL(u).pathname)).status()).toBe(200);
  }
});

test('the sitemap has no duplicate <loc>', async ({ request }) => {
  const xml = await (await request.get('/sitemap.xml')).text();
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  expect(locs.length - new Set(locs).size, 'duplicate <loc> entries').toBe(0);
});

/// **A KNOWN DEFECT, tracked rather than hidden.**
///
/// `notFound()` called from a route that MATCHED — `/this-does-not-exist` hits
/// `app/[slug]/page.tsx` — makes Next 14.2.35 serve `<html id="__next_error__">`
/// with 44 characters of visible text and the generic title. The real 404 UI
/// arrives only in the RSC payload, so a visitor on a slow connection sees a
/// blank white page until the JS lands.
///
/// A route that matches NOTHING (`/a/b/c/d/e`) serves the prerendered
/// `_not-found.html` correctly, 307 visible characters. That contrast is the
/// whole diagnosis: the prerendered page is fine and is simply not used.
///
/// Tried and did not fix it: a not-found boundary colocated in `app/[slug]/`.
/// `force-dynamic` cannot be tested — it is rejected alongside
/// `generateStaticParams`.
///
/// `test.fail()` rather than `skip`: this PASSES while the defect exists and
/// FAILS the day it stops existing, which is when someone should delete it.
/// The assertion must strip `<script>` first. « Page introuvable » IS present
/// in the raw bytes — inside the RSC flight payload — so a plain
/// `toContain` passes while the visitor sees a blank page. The first version of
/// this test did exactly that and reported the defect as fixed.
function visibleText(html: string): string {
  const stripped = html
    .replace(/<script[\s\S]*?<\/script>/g, '')
    .replace(/<style[\s\S]*?<\/style>/g, '')
    .replace(/<[^>]+>/g, ' ');
  return stripped.replace(/\s+/g, ' ').trim();
}

test.fail('KNOWN: notFound() from a matched route serves an empty shell', async ({ request }) => {
  const html = await (await request.get('/this-does-not-exist')).text();
  expect(visibleText(html)).toContain('Page introuvable');
});

test('a route matching nothing serves a real 404 in the HTML', async ({ request }) => {
  // The control for the test above. If this ever breaks too, the diagnosis
  // changes from "notFound() bails" to "the 404 page is broken".
  const res = await request.get('/a/b/c/d/e');
  expect(res.status()).toBe(404);
  expect(visibleText(await res.text())).toContain('Page introuvable');
});
