import { expect, test } from '@playwright/test';

test('landing page lists providers + emits ItemList JSON-LD', async ({
  page,
}) => {
  await page.goto('/coiffure-cocody');

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
});

test('invalid combo → 404', async ({ page }) => {
  const res = await page.goto('/coiffure-nowhere');
  expect(res?.status()).toBe(404);
  await expect(page.getByText('Page introuvable')).toBeVisible();
});
