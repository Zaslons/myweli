import { type Page, expect, test } from '@playwright/test';

/// Multi-pays MP3 (docs/design/multi-pays-end-version.md §9) — the Libreville
/// arc on web: the stub's p3 « Institut Belle Vue » is a GABON salon
/// (Africa/Libreville · XAF · GA), and appt4 is the consumer's booking there.
/// The harness browser runs at TZ UTC (playwright.config), so the +1 salon
/// clock is observable and the salon-time hint MUST show.

async function consumerLogin(page: Page) {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);
}

test('consumer: the Gabon booking renders ITS wall-clock, FCFA from XAF and the country hint', async ({
  page,
}) => {
  await consumerLogin(page);

  // The list: the Abidjan booking keeps 09:00 (bit-identical Wave 0) while
  // the Gabon one — the SAME 09:00Z instant — reads 10:00, salon time.
  const gabonCard = page
    .locator('a', { hasText: 'Institut Belle Vue' })
    .first();
  await expect(gabonCard).toContainText('à 10:00');
  await expect(
    page.locator('a', { hasText: 'Beauté Divine' }).first(),
  ).toContainText('à 09:00');

  // The detail: salon wall-clock + « FCFA » from XAF + the dynamic hint.
  await page.goto('/mon-compte/appt4');
  await expect(page.getByText('à 10:00')).toBeVisible();
  // fr-FR thousands separator = the narrow no-break space (U+202F).
  await expect(
    page.getByText(/15[\s\u202f\u00a0]000[\s\u202f\u00a0]FCFA/).first(),
  ).toBeVisible();
  await expect(
    page.getByText('Heures affichées : heure du salon (Gabon)'),
  ).toBeVisible();
});

test('consumer: the Abidjan booking never shows the hint under a UTC device', async ({
  page,
}) => {
  await consumerLogin(page);
  await page.goto('/mon-compte/appt1');
  await expect(page.getByText('à 09:00')).toBeVisible();
  await expect(page.getByText(/heure du salon/)).toHaveCount(0);
});

test('pro: switching to the Gabon salon re-catalogs the deposit operators', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  // The CI salon offers the CI catalog.
  await page.goto('/pro/acompte');
  await page.getByText('Exiger un acompte').click();
  const operator = page.getByLabel('Opérateur Mobile Money');
  await expect(operator.locator('option', { hasText: 'Wave' })).toHaveCount(1);
  await expect(
    operator.locator('option', { hasText: 'Airtel Money' }),
  ).toHaveCount(0);

  // Switch to Institut Belle Vue (GA) → the GABON catalog.
  await page.getByRole('button', { name: 'Changer de salon' }).click();
  await page.getByRole('button', { name: /Institut Belle Vue/ }).click();
  await expect(
    page.getByRole('button', { name: 'Changer de salon' }),
  ).toContainText('Institut Belle Vue');

  await page.goto('/pro/acompte');
  await page.getByText('Exiger un acompte').click();
  const gaOperator = page.getByLabel('Opérateur Mobile Money');
  await expect(
    gaOperator.locator('option', { hasText: 'Airtel Money' }),
  ).toHaveCount(1);
  await expect(
    gaOperator.locator('option', { hasText: 'Orange Money' }),
  ).toHaveCount(0);
});
