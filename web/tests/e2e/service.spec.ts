import { expect, test } from '@playwright/test';

test('service landing lists matching salons + ItemList JSON-LD', async ({
  page,
}) => {
  await page.goto('/tresses-cocody');

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

test('unknown service combo → 404', async ({ page }) => {
  const res = await page.goto('/tresses-nowhere');
  expect(res?.status()).toBe(404);
});
