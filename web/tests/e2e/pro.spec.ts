import { type Page, expect, test } from '@playwright/test';

async function proLogin(page: Page) {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);
}

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
  // Resend with cooldown (module 11), pro side.
  await expect(page.getByText(/Renvoyer le code \(\d+s\)/)).toBeVisible();
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

  // « Reprogrammer » (parity 1.9): cross-day date + time. 10:00 is the
  // stub's taken slot → 409 copy; 11:00 succeeds and closes the editor.
  await page.getByRole('button', { name: 'Reprogrammer' }).click();
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  await page.getByLabel('Nouvelle date').fill(tomorrow);
  await page.getByLabel('Nouvelle heure').fill('10:00');
  await page.getByRole('button', { name: 'Confirmer', exact: true }).click();
  await expect(
    page.getByText('Créneau indisponible. Choisissez un autre horaire.'),
  ).toBeVisible();
  await page.getByLabel('Nouvelle heure').fill('11:00');
  await page.getByRole('button', { name: 'Confirmer', exact: true }).click();
  await expect(page.getByText('Nouvelle date et heure')).toBeHidden();

  // Parity 1.10: arrival from the detail page (same-day confirmed).
  await page.getByRole('button', { name: 'Client arrivé' }).click();
  await expect(page.getByText(/Arrivé à \d{2}:\d{2}/)).toBeVisible();
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
  // Audit 3.1: the capability block (empty selection = toute l'équipe).
  await expect(page.getByText('Qui peut réaliser ce service ?')).toBeVisible();
  await expect(page.getByRole('checkbox', { name: /Awa/ })).toBeVisible();
  // Audit 3.2: the per-hair-length duration editor.
  await page
    .getByRole('checkbox', { name: 'Durée selon la longueur de cheveux' })
    .click();
  await page.getByLabel('Court (min)').fill('60');
  await page.getByLabel('Nom du service').fill('Coupe homme');
  await page.getByLabel('Prix — à partir de (FCFA)').fill('5000');
  await page.getByLabel('Durée (minutes)').fill('30');
  await page.getByRole('button', { name: 'Enregistrer' }).click();

  await expect(page.getByText('Coupe homme')).toBeVisible();
});

test('catalogue Employés: list fiches + add one', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Catalogue' }).click();
  // Team access R5a: the artists tab is now « Employés » (« Équipe » is the
  // separate members page).
  await page.getByRole('button', { name: 'Employés' }).click();
  await expect(page.getByText('Awa').first()).toBeVisible();

  await page.getByRole('button', { name: 'Ajouter un employé' }).click();
  await page.getByLabel('Nom').fill('Koffi');
  await page.getByLabel('Spécialisation (optionnel)').fill('Barbier');
  // Audit 3.5: the avatar upload (gallery pipeline).
  await page.locator('input[aria-label="Photo de l’employé"]').setInputFiles({
    name: 'avatar.jpg',
    mimeType: 'image/jpeg',
    buffer: Buffer.from('fake-avatar-bytes'),
  });
  await expect(
    page.getByRole('button', { name: 'Changer la photo' }),
  ).toBeVisible();
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

  // Audit 3.8: add a Monday lunch pause, saved in the same PUT.
  await expect(page.getByRole('heading', { name: 'Pauses' })).toBeVisible();
  await page
    .getByRole('checkbox', { name: 'Pause' })
    .first()
    .check();

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

  // Abonnement view — the R5a offer picker (default = live trial).
  await page.getByRole('link', { name: 'Abonnement' }).click();
  await expect(page).toHaveURL(/\/pro\/abonnement/);
  await expect(
    page.getByRole('heading', { name: 'Mon abonnement' }),
  ).toBeVisible();
  await expect(page.getByText(/Essai gratuit/)).toBeVisible();
  // The three offer cards; the current tier is marked « Offre actuelle ».
  await expect(page.getByRole('heading', { name: 'Business' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Réseau' })).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Offre actuelle' }),
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
  // Multi-pays MP3: the commune is a locality PICKER (writes areaId; the
  // server derives commune/ville/fuseau/devise — T57).
  await expect(page.getByLabel('Ville')).toHaveValue('abidjan');
  await expect(page.getByLabel('Commune')).toHaveValue('cocody');
  await page.getByLabel('Commune').selectOption('marcory');
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
  // Seeded with 3 photos → 3 images.
  await expect(page.locator('main img')).toHaveCount(3);

  // Upload a new one (stubbed sign + R2 POST).
  await page
    .locator('input[type=file]')
    .first()
    .setInputFiles({
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      buffer: Buffer.from('fake-jpeg-bytes'),
    });
  await expect(page.locator('main img')).toHaveCount(4);

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

  // Audit 4.1: mint a custom tag (the app's free-text field).
  await page.getByRole('button', { name: 'Modifier les tags' }).click();
  await page.getByLabel('Nouveau tag').fill('Mèches');
  await page.getByRole('button', { name: 'Ajouter le tag' }).click();
  await expect(page.getByText('Mèches')).toBeVisible();
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
  // Multi-service (web-manual-booking.md): both prestations + a note.
  await dialog.getByRole('checkbox').first().check();
  await dialog.getByRole('checkbox').nth(1).check();
  await expect(dialog.getByText(/20\s?000/)).toBeVisible(); // running total
  await dialog
    .getByLabel('Rechercher ou nommer le client')
    .fill('Nouvelle Cliente');
  await dialog.getByLabel('Note').fill('Vient avec ses mèches');
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

test('« + Nouveau rendez-vous » on /pro/rendez-vous books standalone (web-manual-booking.md)', async ({
  page,
}) => {
  await proLogin(page);
  await page.goto('/pro/rendez-vous');
  await page.getByRole('button', { name: '+ Nouveau rendez-vous' }).click();

  const dialog = page.getByRole('dialog', { name: 'Nouveau rendez-vous' });
  await dialog.getByRole('checkbox').first().check();
  // Standalone entry → the dialog owns date & time (future-only).
  await dialog.getByLabel('Date du rendez-vous').fill('2026-12-01');
  await dialog.getByLabel('Heure du rendez-vous').fill('11:00');
  await dialog
    .getByLabel('Rechercher ou nommer le client')
    .fill('Cliente Standalone');
  await dialog.getByRole('button', { name: 'Créer', exact: true }).click();
  await expect(page.getByText('Rendez-vous créé')).toBeVisible();
});

test('client card: « Nouveau rendez-vous » opens the dialog pre-picked (C1b deferral closed)', async ({
  page,
}) => {
  await proLogin(page);
  await page.goto('/pro/clients/sc1');
  await expect(page.getByRole('heading', { name: /Koffi/ })).toBeVisible();
  await page.getByRole('button', { name: 'Nouveau rendez-vous' }).click();

  const dialog = page.getByRole('dialog', { name: 'Nouveau rendez-vous' });
  await expect(dialog.getByText(/Koffi/)).toBeVisible(); // pre-picked client
  await dialog.getByRole('checkbox').first().check();
  await dialog.getByLabel('Date du rendez-vous').fill('2026-12-01');
  await dialog.getByLabel('Heure du rendez-vous').fill('15:00');
  await dialog.getByRole('button', { name: 'Créer', exact: true }).click();
  await expect(page.getByText('Rendez-vous créé')).toBeVisible();
});

test('« Avis » shows the summary + review cards (web-pro-reviews.md)', async ({
  page,
}) => {
  await proLogin(page);
  await page.getByRole('link', { name: 'Avis' }).click();
  await expect(page).toHaveURL(/\/pro\/avis/);

  // Summary card: average of the stubbed 5★ + 4★ reviews.
  await expect(page.getByText('★ 4.5')).toBeVisible();
  await expect(page.getByText('2 avis')).toBeVisible();

  // Cards: author, text, visit context, photo review.
  await expect(page.getByText('Service impeccable.')).toBeVisible();
  await expect(page.getByText(/avec Awa/)).toBeVisible();
  await expect(page.getByText('Mariam')).toBeVisible();
  await expect(page.getByAltText('Photo de l’avis')).toBeVisible();
});

test('« Vérification » : upload des documents KYC → soumission (web-pro-kyc.md)', async ({
  page,
}) => {
  await proLogin(page);
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
  await page.goto('/pro/profil');
  await page.getByRole('link', { name: /Vérification/ }).click();
  await expect(page).toHaveURL(/\/pro\/verification/);
  await expect(page.getByText('Vérification en attente')).toBeVisible();

  // businessType 'other' → the RCCM is optional; ID + selfie required.
  await expect(
    page.getByText('Registre de commerce (RCCM) (optionnel)'),
  ).toBeVisible();
  const submit = page.getByRole('button', {
    name: 'Soumettre pour vérification',
  });
  await expect(submit).toBeDisabled();

  // Add the two required documents (hidden inputs → direct storage POST).
  await page
    .getByLabel('Pièce d’identité (CNI / passeport)', { exact: true })
    .setInputFiles({
      name: 'cni.jpg',
      mimeType: 'image/jpeg',
      buffer: Buffer.from('id-bytes'),
    });
  await expect(page.getByText('Fourni · cni.jpg')).toBeVisible();
  await page.getByLabel('Photo du visage', { exact: true }).setInputFiles({
    name: 'visage.jpg',
    mimeType: 'image/jpeg',
    buffer: Buffer.from('selfie-bytes'),
  });
  await expect(page.getByText('Fourni · visage.jpg')).toBeVisible();

  await submit.click();
  await expect(
    page.getByText('Documents soumis pour vérification'),
  ).toBeVisible();
});

test('go-live: le brouillon complet se met en ligne (pro-salon-lifecycle B2)', async ({
  page,
}) => {
  await proLogin(page);

  // The draft banner + checklist, everything done (complete stub salon).
  await expect(
    page.getByText('Votre salon n’est pas encore en ligne'),
  ).toBeVisible();
  // Counts are order-proof: parallel tests add services/photos to the
  // shared stub salon — the gate (≥3) is what matters.
  await expect(
    page.getByText(/Au moins 3 prestations \(\d+\/3\)/),
  ).toBeVisible();
  await expect(page.getByText(/Au moins 3 photos \(\d+\/3\)/)).toBeVisible();

  // B4: the pre-publish preview — the consumer page, booking disabled.
  await page.getByRole('link', { name: 'Aperçu de ma page' }).click();
  await expect(page).toHaveURL(/\/pro\/apercu/);
  await expect(
    page.getByText(/Aperçu — votre salon n’est pas encore en ligne/),
  ).toBeVisible();
  await expect(
    page.getByRole('heading', { level: 1, name: /Beauté Divine/ }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Réserver' }).first(),
  ).toBeDisabled();
  await page.getByRole('link', { name: '← Tableau de bord' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  const btn = page.getByRole('button', { name: 'Mettre en ligne' });
  await expect(btn).toBeEnabled();
  await btn.click();

  await expect(page.getByText(/Votre salon est en ligne/)).toBeVisible();
  await expect(
    page.getByText('Votre salon n’est pas encore en ligne'),
  ).toHaveCount(0);
});

test('revenus: total + ledger + period tabs (parity 9.1)', async ({ page }) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Revenus' }).click();
  await expect(page).toHaveURL(/\/pro\/revenus/);

  // « Tout » (default): the three stub transactions → 37 000 FCFA.
  await expect(page.getByText(/37\s000\sFCFA/)).toBeVisible();

  // « Aujourd'hui » narrows to today's two transactions (15 000 + the 23:30
  // salon-day-boundary probe — timezone-salon-time.md §8: device-local
  // bucketing used to drop it on non-UTC machines).
  await page.getByRole('button', { name: 'Aujourd’hui' }).click();
  await expect(page.getByText(/17\s000\sFCFA/).first()).toBeVisible();
  await expect(page.getByText(/37\s000\sFCFA/)).toBeHidden();
});

// LAST test in the file: it ends the pro session (stateless stub login —
// other files are unaffected).
test('compte: export buttons + type-SUPPRIMER deletion (audit 11.5)', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Profil', exact: true }).click();
  await expect(page).toHaveURL(/\/pro\/profil/);

  // The export half (AUTH-005).
  await expect(
    page.getByRole('button', { name: 'Exporter (JSON)' }),
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Copier' })).toBeVisible();

  // The deletion half (AUTH-004): gated on the typed confirmation.
  await page.getByRole('button', { name: 'Supprimer mon compte' }).click();
  const confirm = page.getByRole('button', {
    name: 'Supprimer définitivement',
  });
  await expect(confirm).toBeDisabled();
  await page.getByLabel('Confirmation de suppression').fill('SUPPRIMER');
  await expect(confirm).toBeEnabled();
  await confirm.click();
  await expect(page).toHaveURL(/\/pro\/connexion/);
});
