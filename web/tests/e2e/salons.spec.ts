import { type Page, expect, test } from '@playwright/test';

/// Team access R6c — multi-salons on the web (docs/design/
/// team-access-r6-multi-salons.md §6): the sidebar « Mes salons » switcher,
/// the Réseau-gated « Ajouter un salon » arc, and the per-salon reshape.
/// Hermetic: the stub owner owns p1 (« Beauté Divine », live Pro trial) and
/// p3 (« Institut Belle Vue », draft SETUP).

async function proLogin(page: Page) {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);
}

async function openSwitcher(page: Page) {
  const trigger = page.getByRole('button', { name: 'Changer de salon' });
  await expect(trigger).toBeVisible();
  await trigger.click();
}

test('the sidebar switcher lists both salons; picking the second reshapes '
  + 'the dashboard and back', async ({ page }) => {
  await proLogin(page);

  // The switcher shows the active salon; the second row carries the role
  // + draft badge (p1 is also a draft in the stub world — scope by row).
  await openSwitcher(page);
  const secondRow = page.getByRole('button', { name: /Institut Belle Vue/ });
  await expect(secondRow).toBeVisible();
  await expect(secondRow).toContainText('Propriétaire · Brouillon');

  // Switch to the draft second salon.
  await page.getByRole('button', { name: /Institut Belle Vue/ }).click();
  // The page subtree remounts for the new salon: its name heads the
  // dashboard and the draft go-live checklist appears.
  await expect(
    page.getByText('Votre salon n’est pas encore en ligne'),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Changer de salon' }),
  ).toContainText('Institut Belle Vue');

  // And back to the first.
  await openSwitcher(page);
  await page.getByRole('button', { name: /Beauté Divine/ }).click();
  await expect(
    page.getByRole('button', { name: 'Changer de salon' }),
  ).toContainText('Beauté Divine');
});

test('without a live Réseau offer: no CTA on /pro/abonnement and the '
  + 'direct form is refused with the shared copy', async ({ page }) => {
  await proLogin(page);

  await page.getByRole('link', { name: 'Abonnement' }).click();
  await expect(page).toHaveURL(/\/pro\/abonnement/);
  await expect(page.getByText(/Essai gratuit/)).toBeVisible();
  // The default offer is Pro — no add-salon section.
  await expect(page.getByText('Ajouter un salon')).toHaveCount(0);

  // Deep-linking the form is fine; the SERVER refuses the create (T55).
  await page.goto('/pro/salons/nouveau');
  await page
    .getByPlaceholder('Ex : Salon Excellence Yopougon')
    .fill('Salon Bloqué');
  await page.getByRole('button', { name: 'Créer le salon' }).click();
  await expect(page.getByText(/offre Réseau est requise/)).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'Passer à l’offre Réseau' }),
  ).toBeVisible();
});

test('the Réseau arc: switch the offer → the CTA appears → create → land '
  + 'on the new draft, switched', async ({ page }) => {
  await proLogin(page);

  // Move p1 to Réseau (the picker keeps the trial clock).
  await page.getByRole('link', { name: 'Abonnement' }).click();
  const reseau = page
    .locator('section')
    .filter({ has: page.getByRole('heading', { name: 'Réseau' }) });
  await reseau.getByRole('button', { name: 'Passer à cette offre' }).click();

  // The add-salon door opens on the abonnement page — the CTA appearing IS
  // the gate assertion (seat copy can double-match when a parallel test
  // already moved the cap to 15).
  const cta = page.getByRole('link', { name: 'Ajouter un salon' });
  await expect(cta).toBeVisible();
  await cta.click();
  await expect(page).toHaveURL(/\/pro\/salons\/nouveau/);

  // Create the third salon.
  await page
    .getByPlaceholder('Ex : Salon Excellence Yopougon')
    .fill('Salon Trois');
  await page.getByRole('button', { name: 'Créer le salon' }).click();

  // Landed on the dashboard, SWITCHED to the new draft.
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await expect(
    page.getByRole('button', { name: 'Changer de salon' }),
  ).toContainText('Salon Trois');
  await expect(
    page.getByText('Votre salon n’est pas encore en ligne'),
  ).toBeVisible();
});
