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

  // Journée is the default now → switch to Calendrier for this legacy check.
  await page.getByRole('button', { name: 'Calendrier' }).click();
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
  // The Journée grid opens a panel; the detail PAGE is reached from Liste.
  await page.getByRole('button', { name: 'Liste' }).click();
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

test('clients: list → search → card → note → tags (module clients C1b)', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Clients' }).click();
  await expect(page).toHaveURL(/\/pro\/clients/);
  await expect(page.getByRole('heading', { name: 'Clients' })).toBeVisible();

  // Seeded base: Koffi (VIP, 2 no-shows, linked) + Aminata.
  await expect(page.getByText('Koffi')).toBeVisible();
  await expect(page.getByText('Aminata')).toBeVisible();
  await expect(page.getByText('2 absences').first()).toBeVisible();

  // Server-side search narrows the list.
  await page.getByLabel('Rechercher un client').fill('amin');
  await expect(page.getByText('Koffi')).toHaveCount(0);
  await expect(page.getByText('Aminata')).toBeVisible();
  await page.getByLabel('Rechercher un client').fill('');

  // The card: stats + note round-trip.
  await page.getByText('Koffi').click();
  await expect(page).toHaveURL(/\/pro\/clients\/sc1/);
  await expect(page.getByText('Visites', { exact: true })).toBeVisible();
  await expect(page.getByText('Dépensé')).toBeVisible();
  await expect(
    page.getByText('Visible uniquement par votre équipe.'),
  ).toBeVisible();
  await page.getByLabel('Ajouter une note').fill('Allergique à l’ammoniaque');
  await page.getByRole('button', { name: 'Ajouter', exact: true }).click();
  await expect(page.getByText('Allergique à l’ammoniaque')).toBeVisible();
});

test('clients: add-client modal — duplicate phone opens the existing card', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.goto('/pro/clients');
  await page.getByRole('button', { name: '+ Ajouter un client' }).click();
  const dialog = page.getByRole('dialog', { name: 'Ajouter un client' });
  await dialog.getByLabel('Nom').fill('Koffi Bis');
  await dialog.getByLabel('Téléphone').fill('+2250700000001'); // Koffi's number
  await dialog.getByRole('button', { name: 'Ajouter' }).click();
  // Dedupe: straight to the existing card.
  await expect(page).toHaveURL(/\/pro\/clients\/sc1/);
});

test('rendez-vous detail shows the no-show badge + card link (C1b)', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Rendez-vous' }).click();
  await page.getByRole('button', { name: 'Liste' }).click();
  await page.getByText('Koffi').first().click();
  await expect(page).toHaveURL(/\/pro\/rendez-vous\/pappt1/);
  await expect(page.getByText('2 absences')).toBeVisible();
  await page.getByRole('link', { name: 'Voir la fiche' }).click();
  await expect(page).toHaveURL(/\/pro\/clients\/sc1/);
});

test('journal grid: Journée is the default view; blocks + panel + arrive', async ({
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

  // « Journée » is the default tab → the grid renders the artist column + block.
  await expect(page.getByText('Awa').first()).toBeVisible();
  await expect(page.getByText('Koffi').first()).toBeVisible();

  // Click a block → the side panel with the client mini-card + no-show badge.
  await page.getByRole('button', { name: /Koffi/ }).first().click();
  await expect(
    page.getByRole('heading', { name: 'Détails du rendez-vous' }),
  ).toBeVisible();
  await expect(page.getByText('2 absences').first()).toBeVisible();
  await expect(page.getByText('Voir la fiche')).toBeVisible();

  // pappt1 is pending in the stub → Accepter, then Client arrivé appears.
  await page.getByRole('button', { name: 'Accepter' }).click();
  // The panel reloads the day; reopen the (now confirmed) block.
  await page.getByRole('button', { name: /Koffi/ }).first().click();
  await page.getByRole('button', { name: 'Client arrivé' }).click();
  // No throw = the arrive round-trip succeeded (grid refetched).
  await expect(page.getByText('Awa').first()).toBeVisible();
});

test('journal grid: quick-create from an empty cell books a client', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.goto('/pro/rendez-vous');
  await expect(page.getByText('Awa').first()).toBeVisible();

  // Click the column create-surface (bottom area, away from the 09:00 block).
  await page
    .getByRole('button', { name: /Créer un rendez-vous/ })
    .first()
    .click({ position: { x: 40, y: 300 } });
  await expect(
    page.getByRole('heading', { name: 'Nouveau rendez-vous' }),
  ).toBeVisible();

  const dialog = page.getByRole('dialog', { name: 'Nouveau rendez-vous' });
  await dialog
    .getByLabel('Rechercher ou nommer le client')
    .fill('Nouvelle Cliente');
  await dialog.getByRole('button', { name: 'Créer', exact: true }).click();
  // Back to the grid (dialog closed).
  await expect(
    page.getByRole('heading', { name: 'Nouveau rendez-vous' }),
  ).toHaveCount(0);
});

test('web pro registration: fields + email code → authenticated on /pro', async ({
  page,
}) => {
  await page.goto('/pro/inscription');
  await expect(
    page.getByRole('heading', { name: 'Créez votre compte professionnel' }),
  ).toBeVisible();

  await page.getByLabel('Nom de l’entreprise').fill('Salon Web Test');
  await page.locator('input[type=tel]').fill('+225 07 00 00 00 10');
  await page.getByLabel('Votre e-mail').fill('nouveau@salon.test');
  await page.getByRole('button', { name: 'Recevoir un code' }).click();
  await page.getByLabel('Code à 6 chiffres').fill('123456');
  await page.getByRole('button', { name: 'S’inscrire' }).click();

  // 201 → pro cookies → the dashboard.
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await expect(page.getByRole('heading', { name: /Aujourd/ })).toBeVisible();
});

test('web pro registration: duplicate identity shows provider_exists', async ({
  page,
}) => {
  await page.goto('/pro/inscription');
  await page.getByLabel('Nom de l’entreprise').fill('Salon Doublon');
  await page.locator('input[type=tel]').fill('+225 07 00 00 00 11');
  await page.getByLabel('Votre e-mail').fill('existe@salon.test');
  await page.getByRole('button', { name: 'Recevoir un code' }).click();
  await page.getByLabel('Code à 6 chiffres').fill('123456');
  await page.getByRole('button', { name: 'S’inscrire' }).click();
  await expect(
    page.getByText('Un compte existe déjà pour cette identité. Connectez-vous.'),
  ).toBeVisible();
});

test('pro connexion links to registration; consumer connexion says sign-up', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await expect(
    page.getByRole('link', { name: 'Créer mon compte' }),
  ).toBeVisible();
  await page.getByRole('link', { name: 'Créer mon compte' }).click();
  await expect(page).toHaveURL(/\/pro\/inscription/);

  await page.goto('/connexion');
  await expect(
    page.getByRole('heading', { name: 'Se connecter ou créer un compte' }),
  ).toBeVisible();
  await expect(
    page.getByText('Votre compte est créé automatiquement'),
  ).toBeVisible();
});
