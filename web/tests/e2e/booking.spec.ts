import { type Page, expect, test } from '@playwright/test';

import { submitOtpLogin } from './_auth';

/// The K2 booking HUB (docs/design/booking-capacity-web-hub.md §4): the app's
/// order-free flow on web — all three entry orders, the capability rule,
/// variant re-validation, the pay-later deposit proof, rebook prefill.


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
  await submitOtpLogin(page, 'awa@example.com');
  // Parity 2.10 — the app's booking note rides along.
  await page
    .getByLabel('Notes (optionnelles)')
    .fill('Cheveux fragiles, produits doux svp');
  await page.getByRole('button', { name: 'Confirmer la réservation' }).click();
  await expect(page.getByText('Réservation envoyée ✓')).toBeVisible();
});

test.describe('mobile web', () => {
  test.use({ viewport: { width: 375, height: 812 } });

  test('the pinned bottom bar gates then confirms (parity 2.11)', async ({
    page,
  }) => {
    await page.goto('/beaute-divine/reserver');
    // The fixed bar is there from the start, disabled until services + time.
    const bar = page.locator('.fixed.bottom-0');
    await expect(bar).toBeVisible();
    await expect(
      bar.getByRole('button', { name: 'Confirmer', exact: true }),
    ).toBeDisabled();

    await page.getByRole('checkbox').first().click();
    await page.getByRole('radio', { name: /Pas de préférence/ }).click();
    await page
      .getByRole('button', { name: /^\d{2}:\d{2}$/ })
      .first()
      .click();

    const cta = bar.getByRole('button', { name: 'Confirmer', exact: true });
    await expect(cta).toBeEnabled();
    await cta.click();
    await expect(
      page.getByRole('heading', { name: 'Confirmation' }),
    ).toBeVisible();
  });
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
  //
  // The wait is load-bearing and was absent until B10: `onToggleService`
  // enables « Confirmer » *synchronously*, so asserting straight after the
  // click passed before `revalidateSlot` had even been called — and would have
  // stayed green if revalidation cleared the slot, which is the exact
  // behaviour this test exists to check.
  //
  // The wait has to be on the DOM, not on the network. `page.waitForResponse`
  // resolves in the Node process on a CDP event and imposes no ordering on the
  // renderer's `setS` and React commit, so it narrows the window without
  // closing it. « Spécialiste » expanding is a state only `settle`'s trailing
  // `setS(advance(...))` can produce — it is the auto-advance itself — so it
  // cannot be observed before revalidation has been applied.
  await page.getByRole('checkbox').first().click();
  await expect(
    page.getByRole('button', { name: /^Spécialiste/ }),
  ).toHaveAttribute('aria-expanded', 'true');
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
  await submitOtpLogin(page, 'awa@example.com');
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

// docs/design/write-idempotency.md §4 — the answer is lost AFTER the server
// booked (the connection drops on the way back). The page asks again at once
// with the same Idempotency-Key, without a word; the server replays: ONE
// booking, and the deposit sheet — not « Ce créneau vient d'être pris » on
// the client's own slot, nor a second booking.
test('une réponse perdue : redemandée avec la même clé — une seule réservation, et l’acompte', async ({
  page,
  request,
}) => {
  const keys: string[] = [];
  let lose = true;
  await page.route('**/api/bookings', async (route) => {
    keys.push(route.request().headers()['idempotency-key']);
    if (lose) {
      lose = false;
      await route.fetch(); // the server books…
      return route.abort('connectionreset'); // …and its answer never arrives
    }
    return route.continue();
  });
  await page.goto('/institut-acompte/reserver');

  await page.getByRole('checkbox').first().click();
  await page.getByRole('radio', { name: /Pas de préférence/ }).click();
  await page.getByRole('button', { name: /^\d{2}:\d{2}$/ }).first().click();
  await page.getByRole('button', { name: 'Confirmer', exact: true }).click();
  await submitOtpLogin(page, 'awa@example.com');
  await page.getByRole('button', { name: 'Confirmer la réservation' }).click();

  await expect(page.getByText('Réservation envoyée ✓')).toBeVisible();
  await expect(page.getByText(/Acompte à régler/)).toBeVisible();
  // No error said — Next's empty route announcer is an `alert` on every
  // page, so only an alert with words counts (axe.spec.ts, B11).
  expect(
    (await page.getByRole('alert').allTextContents())
      .map((t) => t.trim())
      .filter(Boolean),
  ).toEqual([]);
  await expect(page.getByText(/vient d’être pris/)).toHaveCount(0);
  expect(keys).toHaveLength(2);
  expect(keys[0]).toMatch(/^[A-Za-z0-9_-]{8,128}$/);
  expect(keys[1]).toBe(keys[0]);
  const stub = await request.get(
    `http://127.0.0.1:8787/__stub/bookings?key=${keys[0]}`,
  );
  expect(await stub.json()).toEqual({ created: 1 });
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
