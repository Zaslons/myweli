import { expect, test, type Page } from '@playwright/test';
import { STORE_LINKED_PATHS } from '../../lib/storeLinkedPages';

/// docs/design/app-review-round-2.md §5, on the built app: what a reviewer gets when
/// the app opens one of its five pages of our site.
///
/// **Two readings, because the failures differ.** The raw HTML is what the server
/// sends, RSC payload included: links passed as props to a client component would be
/// there with nothing on the screen, and a link hidden after hydration would be there
/// too. The anchors are what the browser ends up with, body included, so a sign-up
/// link added to a page's text fails here as well as one in the chrome.
///
/// The list is written out rather than imported, and compared to the module: removing a
/// page from the module must fail here, and so must adding one nobody reads here.

const FIVE = ['/support', '/politique-confidentialite', '/cgu', '/mentions-legales', '/suppression-compte'];
const CONTROLS = ['/', '/recherche'];
const SALON_PATHS = ['/professionnels', '/pro/inscription', '/pro/connexion'];
const SALON_WORDS = ['Espace pro', 'Inscrire mon salon', 'Connexion Espace pro', 'MyWeli Pro pour les salons'];
const LEGAL = ['Politique de confidentialité', 'Conditions d’utilisation', 'Mentions légales', 'Supprimer mon compte'];

/// An iPad Air 11-inch in portrait, where Apple's reviewer sat and the header's link
/// shows, and a phone, where it did not show but was still in the HTML.
const WIDTHS: [name: string, width: number, height: number][] = [
  ['iPad', 820, 1180],
  ['phone', 375, 812],
];

const anchorPaths = (page: Page) =>
  page.locator('a[href]').evaluateAll((all) => all.map((a) => new URL((a as HTMLAnchorElement).href).pathname));
const toSalons = (path: string) => path === '/pro' || path.startsWith('/pro/') || path === '/professionnels';

/// React's recoverable hydration errors, minified in a production build. A mismatch
/// means what the server sent is thrown away on load: the flash this must not have.
const collectHydrationErrors = (page: Page) => {
  const errors: string[] = [];
  const read = (text: string) => {
    if (/hydrat|Minified React error #(418|419|422|423|425)/i.test(text)) errors.push(text);
  };
  page.on('pageerror', (e) => read(e.message));
  page.on('console', (m) => {
    if (m.type() === 'error') read(m.text());
  });
  return errors;
};

test('this file reads every page of the module', () => {
  expect([...FIVE].sort()).toEqual([...STORE_LINKED_PATHS].sort());
});

for (const path of FIVE) {
  test(`${path}: the HTML the server sends names no salon link, RSC payload included`, async ({ request }) => {
    const res = await request.get(path);
    expect(res.status()).toBe(200);
    const html = await res.text();
    expect(html, 'the page itself, or this reads an error page').toContain('<h1');
    for (const s of [...SALON_PATHS, ...SALON_WORDS]) {
      expect(html, s).not.toContain(s);
    }
    expect(html).not.toMatch(/facturation|abonnement|FCFA/i);
  });

  for (const [name, width, height] of WIDTHS) {
    test(`${path} on ${name}: no anchor anywhere on the page leads to the salons, and the way home stays`, async ({
      page,
    }) => {
      await page.setViewportSize({ width, height });
      const errors = collectHydrationErrors(page);
      await page.goto(path);
      await page.waitForLoadState('networkidle');

      const anchors = await anchorPaths(page);
      expect(anchors, 'the logo and the breadcrumb, or this read nothing').toContain('/');
      expect(anchors.filter(toSalons)).toEqual([]);
      expect(await page.getByText('Espace pro', { exact: true }).count()).toBe(0);
      expect(errors).toEqual([]);

      await expect(page.getByRole('link', { name: 'MyWeli — accueil' })).toHaveAttribute('href', '/');
      await expect(page.getByRole('navigation', { name: 'Fil d’Ariane' }).getByRole('link')).toHaveAttribute(
        'href',
        '/',
      );
      await expect(page.getByRole('banner').getByRole('link', { name: 'Mon compte' })).toBeVisible();

      const footer = page.getByRole('contentinfo');
      for (const label of LEGAL) await expect(footer.getByRole('link', { name: label })).toBeVisible();
      await expect(page.getByRole('navigation', { name: 'Réseaux sociaux' }).getByRole('link').first()).toBeVisible();
    });
  }
}

for (const path of CONTROLS) {
  test(`control ${path}: the HTML names all three, or the checks above discriminate nothing`, async ({ request }) => {
    const html = await (await request.get(path)).text();
    for (const s of [...SALON_PATHS, ...SALON_WORDS]) expect(html, s).toContain(s);
  });

  test(`control ${path} on iPad: « Espace pro » shows in the header, the group in the footer`, async ({ page }) => {
    // /recherche holds the map. Live basemap traffic stalls networkidle: axe.spec.ts's
    // rule, and this harness has no retry to hide it.
    await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
    await page.setViewportSize({ width: 820, height: 1180 });
    const errors = collectHydrationErrors(page);
    await page.goto(path);
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('banner').getByRole('link', { name: 'Espace pro' })).toBeVisible();
    const group = page.getByRole('navigation', { name: 'Professionnels' });
    expect(await group.getByRole('link').evaluateAll((all) => all.map((a) => a.getAttribute('href')))).toEqual(
      SALON_PATHS,
    );
    expect(errors).toEqual([]);
  });
}

test('control / on a phone: the group is what a phone reaches, so it stays', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/');
  await expect(page.getByRole('navigation', { name: 'Professionnels' }).getByRole('link').first()).toBeVisible();
  await expect(page.getByRole('banner').getByRole('link', { name: 'Espace pro' })).toBeHidden();
});

test.describe('the spellings of a path', () => {
  test('/cgu/ redirects to /cgu, and lands clean', async ({ page, request }) => {
    const res = await request.get('/cgu/', { maxRedirects: 0 });
    expect(res.status()).toBe(308);
    expect(res.headers().location).toBe('/cgu');
    await page.goto('/cgu/');
    await expect(page).toHaveURL(/\/cgu$/);
    expect((await anchorPaths(page)).filter(toSalons)).toEqual([]);
  });

  for (const url of ['/%63gu', '/mentions%2Dlegales']) {
    test(`${url}, percent-encoded, is the same page and no link comes back on load`, async ({ page }) => {
      const errors = collectHydrationErrors(page);
      await page.goto(url);
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
      expect((await anchorPaths(page)).filter(toSalons)).toEqual([]);
      expect(errors).toEqual([]);
    });
  }

  for (const url of ['/cgu?utm_source=x', '/support?a=b#contact']) {
    test(`${url} is the same page`, async ({ page, request }) => {
      const html = await (await request.get(url)).text();
      for (const s of [...SALON_PATHS, ...SALON_WORDS]) expect(html, s).not.toContain(s);
      await page.goto(url);
      await page.waitForLoadState('networkidle');
      expect((await anchorPaths(page)).filter(toSalons)).toEqual([]);
    });
  }
});

test('a client navigation takes the links away and brings them back', async ({ page }) => {
  // No request for a document happens on the way, so a decision made by the server
  // alone would leave them standing on /cgu.
  await page.setViewportSize({ width: 820, height: 1180 });
  await page.goto('/');
  const door = page.getByRole('banner').getByRole('link', { name: 'Espace pro' });
  const group = page.getByRole('navigation', { name: 'Professionnels' });
  await expect(door).toBeVisible();
  await expect(group).toBeVisible();

  await page.getByRole('contentinfo').getByRole('link', { name: 'Conditions d’utilisation' }).click();
  await expect(page).toHaveURL(/\/cgu$/);
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Conditions générales');
  await expect(door).toHaveCount(0);
  await expect(group).toHaveCount(0);

  await page.getByRole('link', { name: 'MyWeli — accueil' }).click();
  await expect(page).toHaveURL(/127\.0\.0\.1:\d+\/$/);
  await expect(door).toBeVisible();
  await expect(group).toBeVisible();
});

test.describe('without the salons’ title, no stray gap above the lists', () => {
  const sentence = (page: Page) => page.getByRole('contentinfo').getByText('MyWeli — réservation');
  const below = async (page: Page, target: ReturnType<Page['locator']>) => {
    const from = (await sentence(page).boundingBox())!;
    const to = (await target.boundingBox())!;
    return to.y - (from.y + from.height);
  };

  for (const [name, width] of [
    ['lg', 1280],
    ['a phone', 375],
  ] as const) {
    test(`at ${name}: the first list starts where the salons’ title starts on /`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 });
      await page.goto('/');
      const title = await below(page, page.locator('#footer-pro'));
      await page.goto('/cgu');
      const list = page.getByRole('navigation', { name: 'Liens légaux' }).getByRole('link').first();
      expect(await below(page, list)).toBeCloseTo(title, 0);
    });
  }

  test('at lg the two groups sit on one line, on the site’s columns', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto('/cgu');
    const legal = (await page.getByRole('navigation', { name: 'Liens légaux' }).boundingBox())!;
    const social = (await page.getByRole('navigation', { name: 'Réseaux sociaux' }).boundingBox())!;
    const text = (await page.getByRole('contentinfo').getByText('MyWeli — réservation').boundingBox())!;
    expect(legal.y).toBeCloseTo(social.y, 0);
    expect(legal.x).toBeCloseTo(text.x, 0);
    expect(social.x).toBeGreaterThan(legal.x + legal.width);
  });
});
