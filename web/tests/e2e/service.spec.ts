import { expect, test } from '@playwright/test';

/// The nested service landing family (multi-pays MP3):
/// /tresses → /tresses/abidjan → /tresses/abidjan/cocody.

test('service area landing lists matching salons + ItemList JSON-LD', async ({
  page,
}) => {
  await page.goto('/tresses/abidjan/cocody');

  await expect(
    page.getByRole('heading', { level: 1, name: 'Tresses & nattes à Cocody' }),
  ).toBeVisible();
  await expect(page.getByText('Beauté Divine')).toBeVisible();

  const blocks = await page
    .locator('script[type="application/ld+json"]')
    .allTextContents();
  const types = blocks.map((t) => JSON.parse(t)['@type']);
  expect(types).toContain('ItemList');
  expect(types).toContain('BreadcrumbList');
});

test('service root + city levels render down the tree', async ({ page }) => {
  await page.goto('/tresses');
  await expect(
    page.getByRole('heading', {
      level: 1,
      name: /Tresses & nattes en Côte d.Ivoire/,
    }),
  ).toBeVisible();

  await page.goto('/tresses/abidjan');
  await expect(
    page.getByRole('heading', { level: 1, name: 'Tresses & nattes à Abidjan' }),
  ).toBeVisible();
  await expect(page.getByText('Beauté Divine')).toBeVisible();
});

test('unknown area under a service root → 404', async ({ page }) => {
  const res = await page.goto('/tresses/abidjan/nowhere');
  expect(res?.status()).toBe(404);
});
