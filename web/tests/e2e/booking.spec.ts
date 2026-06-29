import { expect, test } from '@playwright/test';

test('web booking funnel: service → slot → OTP → confirmed (no install)', async ({
  page,
}) => {
  await page.goto('/beaute-divine/reserver');
  await expect(
    page.getByRole('heading', { level: 1, name: /Réserver chez Beauté Divine/ }),
  ).toBeVisible();

  // Services
  await page.getByRole('checkbox').first().check();
  await page.getByRole('button', { name: 'Continuer' }).click();

  // Staff (default "Sans préférence")
  await page.getByRole('button', { name: 'Continuer' }).click();

  // Slot
  await page.locator('input[type=date]').fill('2026-12-01');
  await page.getByRole('button', { name: /^\d{2}:\d{2}$/ }).first().click();
  await page.getByRole('button', { name: 'Continuer' }).click();

  // Confirm + OTP (stub devCode 123456)
  await page.locator('input[type=tel]').fill('0700000000');
  await page.getByRole('button', { name: 'Envoyer le code' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Confirmer la réservation' }).click();

  await expect(page.getByText('Réservation envoyée ✓')).toBeVisible();
});
