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
