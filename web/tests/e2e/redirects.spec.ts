import { expect, test } from '@playwright/test';

/// Multi-pays MP3 — the legacy flat slugs 308 (≡ 301 for SEO) to their
/// nested homes, in the SAME deploy that ships the nested pages + sitemap;
/// unknown combos stay 404. Plus the route-precedence guards around the new
/// dynamic [city]/[area] segments.

test('flat category slug → 308 → the nested area landing', async ({
  page,
}) => {
  const res = await page.request.get('/coiffure-cocody', {
    maxRedirects: 0,
  });
  expect(res.status()).toBe(308);
  expect(res.headers()['location']).toContain('/coiffure/abidjan/cocody');

  // Following the redirect lands on the real page.
  await page.goto('/coiffure-cocody');
  await expect(page).toHaveURL(/\/coiffure\/abidjan\/cocody$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Coiffure à Cocody' }),
  ).toBeVisible();
});

test('flat service slug (hyphenated root) → 308 → nested', async ({
  page,
}) => {
  const res = await page.request.get('/coupe-homme-plateau', {
    maxRedirects: 0,
  });
  expect(res.status()).toBe(308);
  expect(res.headers()['location']).toContain('/coupe-homme/abidjan/plateau');
});

test('unknown flat combos stay 404', async ({ page }) => {
  const cat = await page.goto('/coiffure-nowhere');
  expect(cat?.status()).toBe(404);
  await expect(page.getByText('Page introuvable')).toBeVisible();
  const svc = await page.goto('/tresses-nowhere');
  expect(svc?.status()).toBe(404);
});

test('precedence: /[provider]/reserver beats the dynamic [city] segment', async ({
  page,
}) => {
  await page.goto('/beaute-divine/reserver');
  await expect(
    page.getByRole('heading', { level: 1, name: /Réserver chez Beauté Divine/ }),
  ).toBeVisible();
});

test('precedence: a provider sub-path that is not reserver → 404', async ({
  page,
}) => {
  // [city] under a NON-taxonomy slug must never render a landing.
  const res = await page.goto('/beaute-divine/abidjan');
  expect(res?.status()).toBe(404);
});
