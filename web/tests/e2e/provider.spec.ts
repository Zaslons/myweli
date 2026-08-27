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

test('gallery: tap a photo → fullscreen lightbox (parity 2.6)', async ({
  page,
}) => {
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Agrandir la photo 1' }).click();
  const box = page.getByRole('dialog', { name: 'Photo du salon' });
  await expect(box).toBeVisible();
  await box.click({ position: { x: 8, y: 8 } });
  await expect(box).toBeHidden();
});

test('reviews: photo lightbox + anonymous « Signaler » prompts login (P2b)', async ({
  page,
}) => {
  await page.goto('/beaute-divine');

  // The stub review carries one photo → thumbnail, then the lightbox.
  const thumb = page.getByRole('button', {
    name: 'Agrandir la photo',
    exact: true,
  });
  await expect(thumb).toBeVisible();
  await thumb.click();
  const lightbox = page.getByRole('dialog', { name: 'Photo de l’avis' });
  await expect(lightbox).toBeVisible();
  await lightbox.click({ position: { x: 8, y: 8 } }); // backdrop closes
  await expect(lightbox).toBeHidden();

  // « Signaler » signed-out → the login prompt with returnTo.
  await page.getByRole('button', { name: 'Signaler', exact: true }).click();
  await page
    .getByRole('button', { name: 'Signaler', exact: true })
    .click();
  await expect(page.getByText('pour signaler cet avis.')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Connectez-vous' })).toHaveAttribute(
    'href',
    '/connexion?returnTo=/beaute-divine',
  );
});

test('provider page: Avant/Après, map, booking panel (M8.2)', async ({
  page,
}) => {
  // Hermetic: the lazy Localisation map must not fetch CARTO from CI.
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
  await page.goto('/beaute-divine');

  // T52/15.1: the « Vérifié » badge on the hero (stub salon is verified).
  await expect(page.getByText('✔ Vérifié')).toBeVisible();

  // Avant/Après section (seeded pair).
  await expect(
    page.getByRole('heading', { name: 'Avant / Après' }),
  ).toBeVisible();
  await expect(page.getByText('Avant', { exact: true }).first()).toBeVisible();

  // Horaires renders the TIME, not the wire (the screenshot bug): the stub
  // now serves the real 2024-01-01T… shape, so both directions discriminate —
  // the formatted range must show AND no ISO residue may reach the page.
  await expect(page.getByText('09:00 – 18:00')).toBeVisible();
  await expect(page.getByText('2024-01-01', { exact: false })).toHaveCount(0);

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
  // §17 — one label. It read « Retour à l'accueil » while mobile and both
  // booking refusals said « Découvrir des salons », same destination.
  await expect(
    page.getByRole('link', { name: 'Découvrir des salons' }),
  ).toHaveAttribute('href', '/');
});

test('a salon that stopped is gone from the public web (Decision C)', async ({
  page,
}) => {
  // `salon-arrete` is the suspended fixture. Before PR1d `by-slug` excluded
  // `draft` only, so an admin-suspended salon stayed publicly readable by slug
  // — the route this page uses.
  const res = await page.goto('/salon-arrete');
  expect(res?.status()).toBe(404);
  await expect(page.getByText('Page introuvable')).toBeVisible();
  // The body already carries the salon case in the right tense, and it has to
  // stay identity-agnostic: this boundary also answers an unknown city.
  await expect(
    page.getByText('Ce salon ou cette page n’existe pas (ou plus).'),
  ).toBeVisible();
});
