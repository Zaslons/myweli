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

test('provider page: Avant/Après, map, booking panel (M8.2)', async ({
  page,
}) => {
  // Hermetic: the lazy Localisation map must not fetch CARTO from CI.
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
  await page.goto('/beaute-divine');

  // Avant/Après section (seeded pair).
  await expect(
    page.getByRole('heading', { name: 'Avant / Après' }),
  ).toBeVisible();
  await expect(page.getByText('Avant', { exact: true }).first()).toBeVisible();

  // Localisation: the shared MapLibre map mounts lazily on approach.
  await page.locator('[aria-label^="Carte"]').scrollIntoViewIfNeeded();
  await expect(page.locator('.maplibregl-map')).toBeVisible();

  // Booking panel: "À partir de" + a Réserver link to the funnel.
  await expect(
    page.getByText('À partir de', { exact: true }).first(),
  ).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'Réserver' }).first(),
  ).toHaveAttribute('href', '/beaute-divine/reserver');
});

test('unknown slug → 404', async ({ page }) => {
  const res = await page.goto('/no-such-salon');
  expect(res?.status()).toBe(404);
  await expect(page.getByText('Page introuvable')).toBeVisible();
});
