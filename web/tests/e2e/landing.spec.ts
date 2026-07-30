import { expect, test } from '@playwright/test';

/// The nested category landing family (multi-pays MP3):
/// /coiffure → /coiffure/abidjan → /coiffure/abidjan/cocody.

test('area landing lists providers + emits ItemList JSON-LD', async ({
  page,
}) => {
  await page.goto('/coiffure/abidjan/cocody');

  await expect(
    page.getByRole('heading', { level: 1, name: 'Coiffure à Cocody' }),
  ).toBeVisible();
  await expect(page.getByText('Beauté Divine')).toBeVisible();

  const blocks = await page
    .locator('script[type="application/ld+json"]')
    .allTextContents();
  const types = blocks.map((t) => JSON.parse(t)['@type']);
  expect(types).toContain('ItemList');
  expect(types).toContain('BreadcrumbList');
  // The breadcrumb walks the full tree: Accueil → root → city → area.
  const crumbs = blocks
    .map((t) => JSON.parse(t))
    .find((b) => b['@type'] === 'BreadcrumbList');
  expect(crumbs.itemListElement).toHaveLength(4);
});

test('city landing: h1, area chips, the citywide grid', async ({ page }) => {
  await page.goto('/coiffure/abidjan');

  await expect(
    page.getByRole('heading', { level: 1, name: 'Coiffure à Abidjan' }),
  ).toBeVisible();
  // The area chip set links down the tree.
  await expect(
    page.getByRole('link', { name: 'Cocody', exact: true }),
  ).toHaveAttribute('href', '/coiffure/abidjan/cocody');
  // The citywide provider grid carries the stub salon.
  await expect(page.getByText('Beauté Divine')).toBeVisible();
});

test('root landing: h1 + the city card down the tree', async ({ page }) => {
  await page.goto('/coiffure');

  await expect(
    // The country name is DATA (straight apostrophe in the seed).
    page.getByRole('heading', { level: 1, name: /Coiffure en Côte d.Ivoire/ }),
  ).toBeVisible();
  await expect(
    page.getByRole('link', { name: /Coiffure à Abidjan/ }),
  ).toHaveAttribute('href', '/coiffure/abidjan');
});

test('unknown city or area under a valid root → 404', async ({ page }) => {
  const badArea = await page.goto('/coiffure/abidjan/nowhere');
  expect(badArea?.status()).toBe(404);
  const badCity = await page.goto('/coiffure/nowhere');
  expect(badCity?.status()).toBe(404);
});
