import { type Page, expect, test } from '@playwright/test';

/// The K2 booking HUB (docs/design/booking-capacity-web-hub.md §4): the app's
/// order-free flow on web — all three entry orders, the capability rule,
/// variant re-validation, the pay-later deposit proof, rebook prefill.

async function loginInline(page: Page) {
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
}

test('services-first: prestations → spécialiste → heure → confirmée', async ({
  page,
}) => {
  await page.goto('/beaute-divine/reserver');
  await expect(
    page.getByRole('heading', { level: 1, name: /Réserver chez Beauté Divine/ }),
  ).toBeVisible();

  // Pick « Tresses » → the hub auto-advances to Spécialiste (the variant
  // default is asserted in the time-first journey, card reopened).
  await page.getByRole('checkbox').first().click();
  await page.getByRole('radio', { name: /Pas de préférence/ }).click();

  // Time section opened by the ordering → slots for today (stub: 3).
  await page.getByRole('button', { name: /^\d{2}:\d{2}$/ }).first().click();

  // Sticky summary gates on services + time; stylist stays optional.
  await page.getByRole('button', { name: 'Confirmer', exact: true }).click();
  await loginInline(page);
  await page.getByRole('button', { name: 'Confirmer la réservation' }).click();
  await expect(page.getByText('Réservation envoyée ✓')).toBeVisible();
});

test('artist-first: Awa → prestations → le prochain créneau se choisit seul', async ({
  page,
}) => {
  await page.goto('/beaute-divine/reserver');

  // Enter through the Spécialiste card.
  await page.getByRole('button', { name: /^Spécialiste/ }).click();
  await page.getByRole('radio', { name: /Awa/ }).click();

  // The ordering sends us to Prestations; picking one triggers the
  // earliest-slot auto-pick (stub: today 09:00) + the hint.
  await page.getByRole('checkbox').first().click();
  await expect(page.getByText(/Prochain créneau :/)).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Confirmer', exact: true }),
  ).toBeEnabled();
});

test('time-first: l’heure choisie survit ou se libère selon la durée', async ({
  page,
}) => {
  await page.goto('/beaute-divine/reserver');

  // Enter through Date et heure (30-min default duration) → pick 10:30.
  await page.getByRole('button', { name: /^Date et heure/ }).click();
  await page.getByRole('button', { name: '10:30' }).click();

  // Ordering → Prestations. Tresses (Moyen, 120 min) still fits 10:30.
  await page.getByRole('checkbox').first().click();
  await expect(
    page.getByRole('button', { name: 'Confirmer', exact: true }),
  ).toBeEnabled();

  // Switch to Long (180 min) → the stub drops 10:30 → the chosen time is
  // silently cleared and the confirm gate closes. (Reopening the card also
  // shows the variant selector defaulted to Moyen.)
  await page.getByRole('button', { name: /^Prestations/ }).click();
  await expect(
    page.getByRole('button', { name: /^Moyen ·/ }),
  ).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('button', { name: /^Long ·/ }).click();
  await expect(
    page.getByRole('button', { name: 'Confirmer', exact: true }),
  ).toBeDisabled();
});

test('capability: une prestation restreinte grise le mauvais spécialiste', async ({
  page,
}) => {
  await page.goto('/beaute-divine/reserver');

  // « Soin visage » is Awa-only → Binta's row is disabled.
  await page.getByRole('checkbox').nth(1).click();
  await expect(page.getByRole('radio', { name: /Binta/ })).toBeDisabled();
  await expect(page.getByRole('radio', { name: /Awa/ })).toBeEnabled();
});

test('acompte: la preuve de paiement se joint dans le flux', async ({
  page,
}) => {
  await page.goto('/institut-acompte/reserver');

  await page.getByRole('checkbox').first().click();
  await page.getByRole('radio', { name: /Pas de préférence/ }).click();
  await page.getByRole('button', { name: /^\d{2}:\d{2}$/ }).first().click();
  await page.getByRole('button', { name: 'Confirmer', exact: true }).click();
  await loginInline(page);
  await page.getByRole('button', { name: 'Confirmer la réservation' }).click();

  // The done step becomes the deposit sheet (server-derived amount).
  await expect(page.getByText('Réservation envoyée ✓')).toBeVisible();
  await expect(page.getByText(/Acompte à régler/)).toBeVisible();
  await expect(page.getByText(/Orange Money/)).toBeVisible();

  await page.setInputFiles('input[type=file]', {
    name: 'preuve.jpg',
    mimeType: 'image/jpeg',
    buffer: Buffer.from('fake-image-bytes'),
  });
  await page.getByRole('button', { name: 'Envoyer la preuve' }).click();
  await expect(
    page.getByText('Acompte envoyé · en attente de confirmation du salon'),
  ).toBeVisible();
});

test('rebook prefill: ?services=s1&artist=a1 arrive sur Date et heure', async ({
  page,
}) => {
  await page.goto('/beaute-divine/reserver?services=s1&artist=a1');

  // Prefilled summaries + the time section already open with slots.
  await expect(page.getByRole('button', { name: /^Prestations/ })).toContainText(
    'Tresses',
  );
  await expect(page.getByRole('button', { name: /^Spécialiste/ })).toContainText(
    'Awa',
  );
  await page.getByRole('button', { name: /^\d{2}:\d{2}$/ }).first().click();
  await expect(
    page.getByRole('button', { name: 'Confirmer', exact: true }),
  ).toBeEnabled();
});
