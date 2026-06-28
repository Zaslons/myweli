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
  await page.locator('input[type=tel]').fill('+2250700000000');
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
