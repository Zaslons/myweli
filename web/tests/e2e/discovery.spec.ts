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

// --- the discovery map (web-discovery-map.md) -------------------------------
// Tile requests are aborted → hermetic; markers/popups are DOM, not tiles.

test('/recherche desktop: list + sticky map, marker → mini-card + card ring', async ({
  page,
}) => {
  await page.route('**/tile.openstreetmap.org/**', (r) => r.abort());
  await page.goto('/recherche');

  // Split view: the list and the map pane are both visible on desktop.
  await expect(page.getByText('Beauté Divine').first()).toBeVisible();
  await expect(page.locator('.leaflet-container')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Autour de moi' })).toBeVisible();

  // Category chips re-query with the type filter.
  await expect(page.getByRole('link', { name: 'Tous' })).toBeVisible();

  // Click the salon's marker → popup mini-card + the list card highlights.
  await page.locator('.myweli-marker').first().click();
  await expect(
    page.locator('.leaflet-popup').getByText('Beauté Divine'),
  ).toBeVisible();
  await expect(
    page.locator('.leaflet-popup').getByRole('link', { name: 'Voir le salon' }),
  ).toHaveAttribute('href', '/beaute-divine');
  await expect(page.locator('.ring-2')).toBeVisible();
});

test('/recherche mobile: « Carte » toggle flips to the map and back', async ({
  page,
}) => {
  await page.route('**/tile.openstreetmap.org/**', (r) => r.abort());
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/recherche');

  await expect(page.getByText('Beauté Divine').first()).toBeVisible();
  await page.getByRole('button', { name: 'Carte', exact: true }).click();
  await expect(page.locator('.leaflet-container')).toBeVisible();
  await page.getByRole('button', { name: 'Liste', exact: true }).click();
  await expect(page.getByText('Beauté Divine').first()).toBeVisible();
});
