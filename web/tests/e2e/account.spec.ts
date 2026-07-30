import { expect, test } from '@playwright/test';

test('unauthenticated /mon-compte redirects to /connexion', async ({ page }) => {
  await page.goto('/mon-compte');
  await expect(page).toHaveURL(/\/connexion/);
  await expect(
    page.getByRole('heading', { name: 'Se connecter' }),
  ).toBeVisible();
});

test('login → see booking → open detail → cancel', async ({ page }) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  // Resend with cooldown (module 11) — counting down, disabled.
  await expect(page.getByText(/Renvoyer le code \(\d+s\)/)).toBeVisible();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();

  await expect(page).toHaveURL(/\/mon-compte/);
  await expect(
    page.getByRole('heading', { name: 'Mon compte' }),
  ).toBeVisible();

  // The enriched booking card → detail.
  await page.getByText('Beauté Divine').first().click();
  await expect(page).toHaveURL(/\/mon-compte\/appt1/);

  // Parity 1.6: contact the salon from the booking.
  await expect(page.getByRole('link', { name: 'Appeler' })).toHaveAttribute(
    'href',
    'tel:+2250700000000',
  );
  await expect(page.getByRole('link', { name: 'WhatsApp' })).toHaveAttribute(
    'href',
    'https://wa.me/2250700000000',
  );

  // P3 — the detail now mirrors the app: calendar, notes, spécialiste.
  await expect(
    page.getByRole('link', { name: 'Ajouter au calendrier (Google)' }),
  ).toHaveAttribute('href', /calendar\.google\.com/);
  await expect(page.getByRole('button', { name: 'Fichier .ics' })).toBeVisible();
  await expect(page.getByText('Cheveux fragiles')).toBeVisible();
  await expect(page.getByText('Spécialiste')).toBeVisible();
  await expect(page.locator('dd').getByText('Awa', { exact: true })).toBeVisible();

  // « Reporter » (parity 1.1): pick tomorrow's 14:00 then confirm.
  await page.getByRole('button', { name: 'Reporter', exact: true }).click();
  await page.getByRole('button', { name: '14:00' }).click();
  await page.getByRole('button', { name: 'Confirmer le report' }).click();
  await expect(page.getByText('Rendez-vous reporté ✓')).toBeVisible();

  await page.getByRole('button', { name: 'Annuler le rendez-vous' }).click();
  await page.getByRole('button', { name: /Confirmer l.annulation/ }).click();

  await expect(page.getByText('Annulé')).toBeVisible();
});

test('M8.3: rebook + review on a completed booking; favoris on /mon-compte', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // Favoris section (seeded providerIds: ['p1']).
  await expect(page.getByRole('heading', { name: 'Favoris' })).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Retirer des favoris' }),
  ).toBeVisible();

  // Completed booking (appt2): rebook + review.
  await page.goto('/mon-compte/appt2');
  await expect(page.getByText('Terminé')).toBeVisible();
  // K2: the rebook link carries the services prefill for the hub.
  await expect(
    page.getByRole('link', { name: 'Réserver à nouveau' }),
  ).toHaveAttribute('href', '/beaute-divine/reserver?services=s1&artist=a1');

  // Leave a review — with a photo (parity 2.13).
  await page.getByRole('radio', { name: '5 étoiles' }).click();
  await page
    .locator('input[type=file]')
    .setInputFiles({
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      buffer: Buffer.from('fake-jpeg-bytes'),
    });
  await expect(page.getByAltText('Pièce jointe 1')).toBeVisible();
  await page.getByRole('button', { name: 'Envoyer l’avis' }).click();
  await expect(page.getByText(/Merci pour votre avis/)).toBeVisible();

  // Signed-in « Signaler » on the public page (parity 2.14).
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Signaler', exact: true }).click();
  await page.getByLabel('Raison du signalement').fill('Contenu déplacé');
  await page.getByRole('button', { name: 'Signaler', exact: true }).click();
  await expect(
    page.getByText('Merci. Notre équipe va examiner cet avis.'),
  ).toBeVisible();
});

test('M8.3: provider favorite toggle → /connexion when signed out', async ({
  page,
}) => {
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Ajouter aux favoris' }).click();
  await expect(page).toHaveURL(/\/connexion/);
});

test('Confidentialité : export des données + suppression type-SUPPRIMER (11.1/11.2)', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // Name edit (11.3).
  await page.getByRole('button', { name: 'Modifier le nom' }).click();
  await page.getByLabel('Nom').fill('Awa K.');
  await page.getByRole('button', { name: 'OK', exact: true }).click();
  await expect(page.getByText('Awa K.')).toBeVisible();

  // Export page (11.2): counts + download/copy actions.
  await page.getByRole('link', { name: 'Exporter mes données' }).click();
  await expect(page).toHaveURL(/\/mon-compte\/donnees/);
  await expect(
    page.getByRole('heading', { name: 'Mes données' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Télécharger (JSON)' }),
  ).toBeVisible();
  await page.getByRole('link', { name: '← Mon compte' }).click();

  // Deletion (11.1): gated on typing SUPPRIMER, then home + signed out.
  await page.getByRole('button', { name: 'Supprimer mon compte' }).click();
  const confirm = page.getByRole('button', { name: 'Supprimer définitivement' });
  await expect(confirm).toBeDisabled();
  await page.getByLabel('Confirmation de suppression').fill('SUPPRIMER');
  await confirm.click();
  await expect(page).toHaveURL(/\/$/);
});

test('notifications: center + Tout lire + préférence (parity 5.1/5.2)', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // Entry point from the account page.
  await page.getByRole('link', { name: 'Notifications' }).click();
  await expect(page).toHaveURL(/\/mon-compte\/notifications/);

  // The unread item shows; « Tout lire » clears the unread state.
  await expect(page.getByText('Rendez-vous confirmé')).toBeVisible();
  await expect(page.getByText('Bienvenue sur MyWeli')).toBeVisible();
  await page.getByRole('button', { name: 'Tout lire' }).click();
  await expect(page.getByRole('button', { name: 'Tout lire' })).toBeHidden();

  // Préférences: toggle marketing off (optimistic, stub-persisted).
  const marketing = page.getByRole('switch', { name: 'Offres & promotions' });
  await expect(marketing).toHaveAttribute('aria-checked', 'true');
  await marketing.click();
  await expect(marketing).toHaveAttribute('aria-checked', 'false');
});

test('P3 extras: proof view, salon visits card, search hearts, support', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // 15.2 — the support entry.
  await expect(
    page.getByRole('link', { name: 'Aide & Support' }),
  ).toHaveAttribute('href', /wa\.me/);

  // 1.3 — « Voir ma capture » on the pending booking with an attached proof.
  await page.goto('/mon-compte/appt3');
  await expect(
    page.getByRole('link', { name: 'Voir ma capture' }),
  ).toHaveAttribute(
    'href',
    '/api/appointments/appt3/deposit-screenshot?redirect=1',
  );

  // 2.7/2.8 — the personal section on the salon page.
  await page.goto('/beaute-divine');
  await expect(page.getByText('Vos rendez-vous ici')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Voir tout' })).toHaveAttribute(
    'href',
    '/mon-compte',
  );
  await expect(
    page.getByRole('link', { name: 'Donner votre avis' }),
  ).toHaveAttribute('href', '/mon-compte/appt2');

  // 2.15 — hearts on the /recherche cards (signed-in toggle).
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
  await page.goto('/recherche?q=tresses');
  const heart = page.getByRole('button', {
    name: /Ajouter Beauté Divine aux favoris|Retirer Beauté Divine des favoris/,
  });
  await expect(heart).toBeVisible();
  const before = await heart.getAttribute('aria-pressed');
  await heart.click();
  await expect(heart).toHaveAttribute(
    'aria-pressed',
    before === 'true' ? 'false' : 'true',
  );
});
