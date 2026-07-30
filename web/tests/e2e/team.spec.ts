import { type Page, expect, test } from '@playwright/test';

import { signInPro } from './_auth';

/// Team access R5a — the owner surfaces on the web (docs/design/
/// web-team-access-r5.md). Hermetic against the stub's team layer: since B10
/// no test in this file writes the salon's offer at all, so the shared
/// go-live/abonnement journeys cannot be disturbed from here. What these tests
/// do mutate is `teamMembers`, which no other spec file writes.


test('Équipe: roster, invite, gates, resend & revoke (full arc)', async ({
  page,
}) => {
  await signInPro(page);

  await page.getByRole('link', { name: 'Équipe' }).click();
  await expect(page).toHaveURL(/\/pro\/equipe/);
  await expect(page.getByRole('heading', { name: 'Équipe' })).toBeVisible();
  // Owner is present; the empty roster invites the team.
  await expect(page.getByText('Propriétaire')).toBeVisible();
  await expect(page.getByText('Invitez votre équipe')).toBeVisible();

  // Invite a manager.
  await page.getByRole('button', { name: '+ Inviter un membre' }).click();
  await page
    .getByPlaceholder('collaborateur@exemple.com')
    .fill('awa.manager@equipe.test');
  await page.getByRole('button', { name: /^Manager/ }).click();
  await page.getByRole('button', { name: 'Envoyer l’invitation' }).click();
  await expect(
    page.getByText('Invitation envoyée à awa.manager@equipe.test.'),
  ).toBeVisible();
  await expect(
    page.getByText('awa.manager@equipe.test', { exact: true }),
  ).toBeVisible();
  await expect(page.getByText(/Invitation envoyée · expire le/)).toBeVisible();

  // Re-inviting the same email → member_exists.
  await page.getByRole('button', { name: '+ Inviter un membre' }).click();
  await page
    .getByPlaceholder('collaborateur@exemple.com')
    .fill('awa.manager@equipe.test');
  await page.getByRole('button', { name: /^Manager/ }).click();
  await page.getByRole('button', { name: 'Envoyer l’invitation' }).click();
  await expect(
    page.getByText('Cette personne est déjà dans l’équipe.'),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Annuler' }).click();

  // Resend the pending invitation.
  await page
    .getByRole('button', { name: 'Actions pour awa.manager@equipe.test' })
    .click();
  await page
    .getByRole('button', { name: /Renvoyer l’invitation \(3 restants\)/ })
    .click();
  await expect(
    page.getByText('Invitation renvoyée à awa.manager@equipe.test.'),
  ).toBeVisible();

  // Revoke, with the account-safe confirmation copy.
  await page
    .getByRole('button', { name: 'Actions pour awa.manager@equipe.test' })
    .click();
  await page.getByRole('button', { name: 'Révoquer l’accès' }).click();
  await expect(
    page.getByText(/perdra immédiatement l’accès à Beauté Divine/),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Révoquer', exact: true }).click();
  await expect(page.getByText('Accès révoqué')).toBeVisible();
});

// The « Abonnement » arc lived here until B10 and now lives in
// `salons.spec.ts`, next to the only other test that writes the salon's offer.
// Two files switching one stub singleton in opposite directions is not a
// timing bug and no wait fixes it — docs/design/web-b10-flake.md §4.2.

test('Login bridge: an invited email joins from « Invitations »', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('invitee@equipe.test');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();

  // The 202 bridge → the invitations step (no session yet).
  await expect(page.getByText(/vous invite comme Manager/)).toBeVisible();
  await expect(page).toHaveURL(/\/pro\/connexion/);

  // Joining signs in and lands on the dashboard.
  await page.getByRole('button', { name: 'Rejoindre' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await expect(page.getByRole('heading', { name: /Aujourd/ })).toBeVisible();
});
