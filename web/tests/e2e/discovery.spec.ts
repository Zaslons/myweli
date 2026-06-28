import { expect, test } from '@playwright/test';

test('home: hero, categories, directory, FAQ + WebSite JSON-LD', async ({
  page,
}) => {
  await page.goto('/');
  await expect(
    page.getByRole('heading', {
      level: 1,
      name: /Réservez beauté & bien-être à Abidjan/,
    }),
  ).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Catégories' })).toBeVisible();
  await expect(
    page.getByRole('heading', { name: 'Partout à Abidjan' }),
  ).toBeVisible();
  // Directory links to the existing SEO landings.
  await expect(
    page.getByRole('link', { name: 'Coiffure à Cocody' }),
  ).toHaveAttribute('href', '/coiffure-cocody');
  // WebSite + SearchAction JSON-LD present.
  const ld = await page
    .locator('script[type="application/ld+json"]')
    .allTextContents();
  expect(ld.join(' ')).toContain('SearchAction');
});

test('home search: service + commune → existing landing', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Service ou salon').fill('Coiffure');
  await page.getByLabel('Commune').fill('Cocody');
  await page.getByRole('button', { name: 'Rechercher' }).click();
  await expect(page).toHaveURL(/\/coiffure-cocody/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Coiffure à Cocody' }),
  ).toBeVisible();
});

test('/recherche lists matching salons', async ({ page }) => {
  await page.goto('/recherche?q=tresses');
  await expect(
    page.getByRole('heading', { name: /Recherche/ }),
  ).toBeVisible();
  await expect(page.getByText('Beauté Divine').first()).toBeVisible();
});
