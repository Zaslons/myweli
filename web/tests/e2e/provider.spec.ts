import { expect, test } from '@playwright/test';

const localBusinessTypes = [
  'HairSalon',
  'NailSalon',
  'DaySpa',
  'HealthAndBeautyBusiness',
];

test('provider page renders sections + valid structured data', async ({
  page,
}) => {
  await page.goto('/beaute-divine');

  await expect(
    page.getByRole('heading', { level: 1, name: 'Beauté Divine' }),
  ).toBeVisible();
  await expect(page.getByText('Services & tarifs')).toBeVisible();
  await expect(page.getByText('Tresses', { exact: true })).toBeVisible();
  await expect(page.getByText(/Avis \(/)).toBeVisible();
  await expect(page.getByText('Questions fréquentes')).toBeVisible();

  // JSON-LD: a LocalBusiness + a FAQPage, both parseable.
  const blocks = await page
    .locator('script[type="application/ld+json"]')
    .allTextContents();
  const types = blocks.map((t) => JSON.parse(t)['@type']);
  expect(types).toContain('FAQPage');
  expect(types.some((t) => localBusinessTypes.includes(t))).toBe(true);
});

test('unknown slug → 404', async ({ page }) => {
  const res = await page.goto('/no-such-salon');
  expect(res?.status()).toBe(404);
  await expect(page.getByText('Page introuvable')).toBeVisible();
});
