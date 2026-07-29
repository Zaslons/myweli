import { type Page, expect, test } from '@playwright/test';

import { signInPro } from './_auth';

/// Team access R6c — multi-salons on the web (docs/design/
/// team-access-r6-multi-salons.md §6): the sidebar « Mes salons » switcher,
/// the Réseau-gated « Ajouter un salon » arc, and the per-salon reshape.
/// Hermetic: the stub owner owns p1 (« Beauté Divine », live Pro trial) and
/// p3 (« Institut Belle Vue », draft SETUP).


/// **This file is an ordered chain, and says so.**
///
/// Its tests establish each other's preconditions on the stub's single
/// `salonOffers` entry: the no-Réseau test must see the seeded Pro trial, the
/// Abonnement test leaves Business, the Réseau arc leaves Réseau. That was
/// already true before B10 and was held up only by the global
/// `fullyParallel: false` — a flag in another file that nothing here declared a
/// dependency on. Stating it locally means flipping that flag can no longer
/// silently shuffle these four into a race.
test.describe.configure({ mode: 'serial' });

async function openSwitcher(page: Page) {
  const trigger = page.getByRole('button', { name: 'Changer de salon' });
  await expect(trigger).toBeVisible();
  await trigger.click();
}

test('the sidebar switcher lists both salons; picking the second reshapes '
  + 'the dashboard and back', async ({ page }) => {
  await signInPro(page);

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
  await signInPro(page);

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

/// Moved here from `team.spec.ts` by B10 (docs/design/web-b10-flake.md §4.2).
///
/// `salonOffers['p1']` is a singleton in the stub and this test and the Réseau
/// arc below were its only two writers — one switching to Business, the other
/// to Réseau, from two files that run on different workers. When the Business
/// write landed between the Réseau write and the create POST, the server
/// answered 403 `reseau_required` and the arc failed on a *stable* wrong URL:
/// a 403, not a slow redirect, so no wait would ever have fixed it (measured
/// 2 failures in 29 runs).
///
/// `fullyParallel: false` serialises tests **within** a file, so co-locating
/// the two writers makes the conflict structurally impossible rather than
/// merely unlikely. Order matters and is load-bearing: the no-offer test above
/// must see the seeded Pro trial, this one leaves Business, and the arc below
/// switches to Réseau — each precondition is established by the test before it.
test('Abonnement: the live-trial banner, the cards & switching offer',
  async ({ page }) => {
    await signInPro(page);
    await page.getByRole('link', { name: 'Abonnement' }).click();
    await expect(page).toHaveURL(/\/pro\/abonnement/);

    await expect(page.getByText(/Essai gratuit/)).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Pro' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Business' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Réseau' })).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Offre actuelle' }),
    ).toBeVisible();
    // The kept-trial reassurance.
    await expect(
      page.getByText('Le changement d’offre conserve votre période d’essai.'),
    ).toBeVisible();

    // Switch to Business → the seat cap grows to 15 and Business becomes
    // current.
    const business = page
      .locator('section')
      .filter({ has: page.getByRole('heading', { name: 'Business' }) });
    await business
      .getByRole('button', { name: 'Passer à cette offre' })
      .click();
    await expect(page.getByText(/\/ 15 places/)).toBeVisible();
  });

test('the Réseau arc: switch the offer → the CTA appears → create → land '
  + 'on the new draft, switched', async ({ page }) => {
  await signInPro(page);

  // Move p1 to Réseau (the picker keeps the trial clock).
  await page.getByRole('link', { name: 'Abonnement' }).click();
  const reseau = page
    .locator('section')
    .filter({ has: page.getByRole('heading', { name: 'Réseau' }) });
  await reseau.getByRole('button', { name: 'Passer à cette offre' }).click();

  // The add-salon door opens on the abonnement page — the CTA appearing IS the
  // gate assertion. The seat copy cannot serve as one: the stub's caps are
  // `business: 15, reseau: 15`, so « / 15 places » renders on two cards at
  // once. B10 corrected the reason recorded here — it read "when a parallel
  // test already moved the cap", which blamed a race for what is simply two
  // tiers sharing a number.
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
