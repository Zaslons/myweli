import { expect, test } from '@playwright/test';

test('unauthenticated /pro redirects to /pro/connexion', async ({ page }) => {
  await page.goto('/pro');
  await expect(page).toHaveURL(/\/pro\/connexion/);
  await expect(
    page.getByRole('heading', { name: 'Espace Pro' }),
  ).toBeVisible();
});

test('provider login → Aujourd’hui shows today’s bookings', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();

  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await expect(
    page.getByRole('heading', { name: /Aujourd/ }),
  ).toBeVisible();
  // The enriched today booking row (service name mapped from the salon).
  await expect(page.getByText('Tresses')).toBeVisible();
});

test('Rendez-vous mirrors the app: Calendrier + Liste show today’s booking', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Rendez-vous' }).click();
  await expect(page).toHaveURL(/\/pro\/rendez-vous/);
  await expect(
    page.getByRole('heading', { name: 'Rendez-vous' }),
  ).toBeVisible();

  // Calendrier (default): today is selected → today's booking shows.
  await expect(page.getByText('Tresses').first()).toBeVisible();

  // Liste → Aujourd'hui sub-tab also shows it.
  await page.getByRole('button', { name: 'Liste' }).click();
  await expect(page.getByText('Tresses').first()).toBeVisible();
});

test('pro detail: open a pending booking → Accepter → Confirmé', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Rendez-vous' }).click();
  // Open the booking (Calendrier default → today's row links to detail).
  await page.getByText('Koffi').first().click();
  await expect(page).toHaveURL(/\/pro\/rendez-vous\/pappt1/);
  await expect(
    page.getByRole('heading', { name: 'Détails du rendez-vous' }),
  ).toBeVisible();
  await expect(page.getByText('En attente')).toBeVisible();

  await page.getByRole('button', { name: 'Accepter' }).click();
  await expect(page.getByText('Confirmé')).toBeVisible();
});

test('catalogue: list services + add one', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Catalogue' }).click();
  await expect(page).toHaveURL(/\/pro\/catalogue/);
  await expect(page.getByText('Tresses').first()).toBeVisible();

  await page.getByRole('button', { name: 'Ajouter un service' }).click();
  await page.getByLabel('Nom du service').fill('Coupe homme');
  await page.getByLabel('Prix — à partir de (FCFA)').fill('5000');
  await page.getByLabel('Durée (minutes)').fill('30');
  await page.getByRole('button', { name: 'Enregistrer' }).click();

  await expect(page.getByText('Coupe homme')).toBeVisible();
});

test('catalogue Équipe: list members + add one', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Catalogue' }).click();
  await page.getByRole('button', { name: 'Équipe' }).click();
  await expect(page.getByText('Awa').first()).toBeVisible();

  await page.getByRole('button', { name: 'Ajouter un membre' }).click();
  await page.getByLabel('Nom').fill('Koffi');
  await page.getByLabel('Spécialisation (optionnel)').fill('Barbier');
  await page.getByRole('button', { name: 'Enregistrer' }).click();

  await expect(page.getByText('Koffi')).toBeVisible();
});

test('disponibilités: edit hours + save', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Disponibilités' }).click();
  await expect(page).toHaveURL(/\/pro\/disponibilites/);
  await expect(
    page.getByRole('heading', { name: 'Disponibilités' }),
  ).toBeVisible();

  // Monday is seeded open 09:00–18:00; change the end time then save.
  await page.getByLabel('Lundi fin').fill('17:00');
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await expect(page.getByText('Disponibilités enregistrées.')).toBeVisible();
});

test('abonnement shows trial status + revenue on the home', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  // G3: revenue card on the home (stub monthRevenue = 45 000).
  await expect(page.getByText('Revenus ce mois')).toBeVisible();

  // Abonnement view.
  await page.getByRole('link', { name: 'Abonnement' }).click();
  await expect(page).toHaveURL(/\/pro\/abonnement/);
  await expect(
    page.getByRole('heading', { name: 'Mon abonnement' }),
  ).toBeVisible();
  await expect(page.getByText(/Essai gratuit/)).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'Nous contacter' }),
  ).toBeVisible();
});

test('profil: edit + save; acompte: enable + save', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Profil', exact: true }).click();
  await expect(page).toHaveURL(/\/pro\/profil/);
  await page.getByLabel('Nom du salon').fill('Beauté Divine Web');
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await expect(page.getByText('Profil enregistré.')).toBeVisible();

  // Into Acompte via the section link.
  await page.getByRole('link', { name: 'Acompte' }).click();
  await expect(page).toHaveURL(/\/pro\/acompte/);
  await page.getByText('Exiger un acompte').click();
  await page.getByLabel('Pourcentage de l’acompte (%)').fill('30');
  await page.getByLabel('Opérateur Mobile Money').selectOption('wave');
  await page.getByLabel('Numéro Mobile Money').fill('+2250700000000');
  await page.getByRole('button', { name: 'Enregistrer' }).click();
  await expect(page.getByText('Acompte enregistré.')).toBeVisible();
});

test('médias: manage photos (remove + save) + upload a new one', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.goto('/pro/medias');
  await expect(
    page.getByRole('heading', { name: 'Médias' }),
  ).toBeVisible();
  // Seeded with 2 photos → 2 images.
  await expect(page.locator('main img')).toHaveCount(2);

  // Upload a new one (stubbed sign + R2 POST).
  await page
    .locator('input[type=file]')
    .first()
    .setInputFiles({
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      buffer: Buffer.from('fake-jpeg-bytes'),
    });
  await expect(page.locator('main img')).toHaveCount(3);

  await page.getByRole('button', { name: 'Enregistrer' }).first().click();
  await expect(page.getByText('Photos enregistrées.')).toBeVisible();
});
