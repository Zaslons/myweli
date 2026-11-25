import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { expect, test, type APIRequestContext } from '@playwright/test';

/// B18 — a salon's page works the moment it is public (the « live fallback »).
/// docs/design/web-salon-page-live-fallback.md §8.1.
///
/// **The defect, measured on production 2026-11-25.** `app/[slug]` builds its
/// salons ahead of time and closes its params; search reads the API live. A
/// salon validated after the last build was listed by search while its page
/// answered « Page introuvable », until the rebuild went live minutes later.
///
/// The stub models that: `salon-juste-valide` is public by slug and listed by
/// `/recherche?q=juste`, and absent from `/sitemap/providers`, so the build does
/// not prerender it. Cases 1–3 were red on the code before the fallback.

const STUB = `http://127.0.0.1:${process.env.STUB_PORT ?? '8787'}`;
const NEW = { slug: 'salon-juste-valide', name: 'Salon Juste Validé' };
const BUILT = 'beaute-divine';

/// What a visitor sees before any script runs (served-html.spec.ts's rule: the
/// flight payload holds the page's text too, so scripts are stripped first).
function visibleText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/g, '')
    .replace(/<style[\s\S]*?<\/style>/g, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function bySlugCalls(request: APIRequestContext, slug: string): Promise<number> {
  const res = await request.get(`${STUB}/__stub/by-slug-calls?slug=${encodeURIComponent(slug)}`);
  expect(res.ok(), 'the stub counts by-slug reads').toBe(true);
  return ((await res.json()) as { calls: number }).calls;
}

test('1. a public salon the build does not have: its own page, server-rendered', async ({
  request,
}) => {
  const res = await request.get(`/${NEW.slug}`, { maxRedirects: 0 });
  expect(res.status(), 'before the fallback this was the 404').toBe(200);
  expect(res.headers()['x-myweli-salon-page'], 'served by the fallback').toBe('live');
  const html = await res.text();
  expect(visibleText(html)).toContain(NEW.name);
  expect(visibleText(html)).not.toContain('Page introuvable');
  expect(html, 'the canonical is the salon address, not the live route').toMatch(
    new RegExp(`<link rel="canonical" href="[^"]*/${NEW.slug}"`),
  );
});

test('2a. from search, a click on its card opens the salon page', async ({ page }) => {
  await page.goto('/recherche?q=juste');
  // The card is a plain <a> (ProviderCard.tsx): a full page load, as for every
  // salon. Before the fallback it landed on « Page introuvable ».
  await page.locator(`main a[href="/${NEW.slug}"]`).first().click();
  await expect(page).toHaveURL(new RegExp(`/${NEW.slug}$`));
  // Contains, not equals: a verified salon's heading also holds « ✔ Vérifié ».
  await expect(page.getByRole('heading', { level: 1 })).toContainText(NEW.name);
});

test('2b. a client navigation to it renders it, with no reload', async ({ page }) => {
  // The map popup's « Voir le salon » is a next/link (ResultsMap.tsx): a client
  // navigation, whose RSC request goes through the middleware's rewrite. Driven
  // here through Next's own router, the call that link makes, so the test does
  // not depend on a map tile being drawn.
  await page.goto('/recherche?q=juste');
  await page.evaluate(() => {
    (window as unknown as { __b18: string }).__b18 = 'same document';
  });
  await page.evaluate((slug) => {
    (window as unknown as { next: { router: { push: (h: string) => void } } }).next.router.push(
      `/${slug}`,
    );
  }, NEW.slug);
  await expect(page).toHaveURL(new RegExp(`/${NEW.slug}$`));
  await expect(page.getByRole('heading', { level: 1 })).toContainText(NEW.name);
  // A 404 makes Next fall back to a full page load (doMpaNavigation), which
  // drops this marker: that is what happened before the fallback.
  expect(
    await page.evaluate(() => (window as unknown as { __b18?: string }).__b18),
    'the page reloaded: the navigation hit a 404',
  ).toBe('same document');
});

test('3. every salon search lists answers 200 (search never lists a page the site cannot serve)', async ({
  page,
  request,
}) => {
  await page.goto('/recherche?q=juste');
  const hrefs = await page
    .locator('main a[href]')
    .evaluateAll((as) => as.map((a) => a.getAttribute('href') ?? ''));
  const salons = [...new Set(hrefs.filter((h) => h === `/${BUILT}` || h === `/${NEW.slug}`))];
  expect(salons.sort(), 'both salons are listed').toEqual([`/${BUILT}`, `/${NEW.slug}`]);
  for (const href of salons) {
    // No redirect followed: a 307 to some 200 would pass otherwise.
    const res = await request.get(href, { maxRedirects: 0 });
    expect(res.status(), `${href} is listed by search`).toBe(200);
  }
});

test('4. the live route has no address of its own', async ({ request }) => {
  for (const path of [
    `/recherche/salon/${BUILT}`,
    `/recherche/salon/${NEW.slug}`,
    '/recherche/salon/inconnu',
    '/recherche/salon',
  ]) {
    const res = await request.get(path, { maxRedirects: 0 });
    expect(res.status(), `${path} must not be a page`).toBe(404);
    expect(visibleText(await res.text()), `${path}: the real 404, not a blank shell`).toContain(
      'Page introuvable',
    );
  }
});

test('5. a built salon is served by the build, with no API read from the middleware', async ({
  request,
}) => {
  // Warm first: the page is ISR (revalidate = 300), and a long run can find it
  // stale, whose background revalidation reads this salon by slug. Once
  // revalidated it is fresh for 300 s, so any read counted below is the
  // middleware's.
  await request.get(`/${BUILT}`, { maxRedirects: 0 });
  await new Promise((r) => setTimeout(r, 1500));
  const before = await bySlugCalls(request, BUILT);
  const res = await request.get(`/${BUILT}`, { maxRedirects: 0 });
  expect(res.status()).toBe(200);
  expect(res.headers()['x-myweli-salon-page']).toBeUndefined();
  expect(await bySlugCalls(request, BUILT), 'the middleware asked about a built salon').toBe(
    before,
  );
});

test('6. the live page hydrates cleanly, with the chrome of a built salon page', async ({
  page,
}) => {
  const errors: string[] = [];
  // A production build reports hydration errors through `reportError`, which
  // Playwright surfaces as `pageerror`, not as a console warning.
  page.on('pageerror', (e) => errors.push(e.message));
  // Anchored on the salon's own heading, not `networkidle`: a salon page loads
  // images and a map, and axe.spec.ts records how `networkidle` flakes there.
  const headerLinks = async (path: string, name: string) => {
    await page.goto(path);
    await expect(page.getByRole('heading', { level: 1 })).toContainText(name);
    await page.waitForLoadState('load');
    // Hydration finishes after `load`; a mismatch is reported then.
    await page.waitForTimeout(500);
    // The header carries the salon's own « Réserver » (`/<slug>/reserver`).
    const slug = path.slice(1);
    return (
      await page.locator('header a[href]').evaluateAll((as) => as.map((a) => a.getAttribute('href')))
    ).map((h) => (h ?? '').replace(`/${slug}/`, '/{salon}/'));
  };
  const built = await headerLinks(`/${BUILT}`, 'Beauté Divine');
  const live = await headerLinks(`/${NEW.slug}`, NEW.name);
  expect(errors, 'no error while rendering or hydrating').toEqual([]);
  // The chrome branches on usePathname (SiteChrome, FooterMark, FooterGroups);
  // a live page must take the branch a salon page takes.
  expect(live.length).toBeGreaterThan(0);
  expect(live).toEqual(built);
});

test('7. no route Next built costs an API read: the route list is complete', async ({
  request,
}) => {
  // Next's own output, an oracle independent of the list the middleware holds
  // (tool/salon-build-list.mjs scans app/; scanning it again here would be
  // circular).
  const manifest = JSON.parse(
    readFileSync(resolve(__dirname, '../../.next/app-path-routes-manifest.json'), 'utf8'),
  ) as Record<string, string>;
  const firsts = [
    ...new Set(
      Object.values(manifest)
        .map((route) => route.split('/')[1] ?? '')
        .filter((seg) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(seg)),
    ),
  ].sort();
  expect(firsts, 'Next built the site’s own routes').toEqual(
    expect.arrayContaining(['cgu', 'connexion', 'pro', 'recherche']),
  );
  for (const seg of firsts) {
    const before = await bySlugCalls(request, seg);
    await request.get(`/${seg}`, { maxRedirects: 0 });
    expect(await bySlugCalls(request, seg), `/${seg} made the middleware ask the API`).toBe(
      before,
    );
  }
});

test('8. the compiled matcher takes a salon path and the live route, and nothing else', () => {
  const manifest = JSON.parse(
    readFileSync(resolve(__dirname, '../../.next/server/middleware-manifest.json'), 'utf8'),
  ) as { middleware: Record<string, { matchers: { regexp: string }[] }> };
  const matchers = Object.values(manifest.middleware).flatMap((m) =>
    m.matchers.map((x) => new RegExp(x.regexp)),
  );
  const runs = (path: string) => matchers.some((re) => re.test(path));
  // Next 14.2 appends `(.json)?` to each source: a bare '/:slug' matched none
  // of the salon paths (measured in a probe build).
  expect(runs('/test-3'), 'a salon path enters the middleware').toBe(true);
  expect(runs(`/${NEW.slug}`)).toBe(true);
  expect(runs('/recherche/salon/x'), 'the live route enters it, to be hidden').toBe(true);
  expect(runs('/test-3/reserver'), 'the funnel never does').toBe(false);
  expect(runs('/favicon.ico'), 'a dotted file never does').toBe(false);
  expect(runs('/coiffure/abidjan/cocody'), 'a landing never does').toBe(false);
});
