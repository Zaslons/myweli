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
  await page.locator('input[type=tel]').fill('+2250700000000');
  await page.getByRole('button', { name: 'Envoyer le code' }).click();
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
  await page.locator('input[type=tel]').fill('+2250700000000');
  await page.getByRole('button', { name: 'Envoyer le code' }).click();
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
  await page.locator('input[type=tel]').fill('+2250700000000');
  await page.getByRole('button', { name: 'Envoyer le code' }).click();
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
  await page.locator('input[type=tel]').fill('+2250700000000');
  await page.getByRole('button', { name: 'Envoyer le code' }).click();
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
