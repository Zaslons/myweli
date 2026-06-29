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
  await page.locator('input[type=tel]').fill('0700000000');
  await page.getByRole('button', { name: 'Envoyer le code' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();

  await expect(page).toHaveURL(/\/mon-compte/);
  await expect(
    page.getByRole('heading', { name: 'Mon compte' }),
  ).toBeVisible();

  // The enriched booking card → detail.
  await page.getByText('Beauté Divine').first().click();
  await expect(page).toHaveURL(/\/mon-compte\/appt1/);

  await page.getByRole('button', { name: 'Annuler le rendez-vous' }).click();
  await page.getByRole('button', { name: /Confirmer l.annulation/ }).click();

  await expect(page.getByText('Annulé')).toBeVisible();
});

test('M8.3: rebook + review on a completed booking; favoris on /mon-compte', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=tel]').fill('0700000000');
  await page.getByRole('button', { name: 'Envoyer le code' }).click();
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
  await expect(
    page.getByRole('link', { name: 'Réserver à nouveau' }),
  ).toHaveAttribute('href', '/beaute-divine/reserver');

  // Leave a review.
  await page.getByRole('button', { name: '5 étoiles' }).click();
  await page.getByRole('button', { name: 'Envoyer l’avis' }).click();
  await expect(page.getByText(/Merci pour votre avis/)).toBeVisible();
});

test('M8.3: provider favorite toggle → /connexion when signed out', async ({
  page,
}) => {
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Ajouter aux favoris' }).click();
  await expect(page).toHaveURL(/\/connexion/);
});
