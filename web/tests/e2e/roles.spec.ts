import { type Page, expect, test } from '@playwright/test';

/// Team access R5b — the role-shaped web (docs/design/web-team-access-r5.md
/// §2.4). Hermetic: member logins get role tokens from the stub; the owner
/// journeys elsewhere are untouched.

async function loginAs(page: Page, email: string) {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill(email);
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
}

test('manager: filtered sidebar, identity block, counts sans revenus', async ({
  page,
}) => {
  await loginAs(page, 'awa.manager@equipe.test');
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  // The capability sidebar: management entries yes, owner-only entries no.
  await expect(page.getByRole('link', { name: 'Catalogue' })).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'Disponibilités' }),
  ).toBeVisible();
  await expect(page.getByRole('link', { name: 'Avis' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Équipe' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Revenus' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Abonnement' })).toHaveCount(0);

  // The member identity block: who, as what, where.
  await expect(page.getByText('awa.manager@equipe.test')).toBeVisible();
  await expect(page.getByText('Manager', { exact: true })).toBeVisible();

  // Dashboard: counts yes, the money row NEVER (field-gated server-side).
  await expect(page.getByText('À confirmer')).toBeVisible();
  await expect(page.getByText('Revenus ce mois')).toHaveCount(0);
  // Owner-only cards are absent.
  await expect(page.getByText('Configurer mon profil')).toBeVisible();
});

test('réception: the reduced sidebar (planning + clients + profil)', async ({
  page,
}) => {
  await loginAs(page, 'fatou.reception@equipe.test');
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await expect(page.getByRole('link', { name: 'Clients' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Rendez-vous' })).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'Profil', exact: true }),
  ).toBeVisible();
  await expect(page.getByRole('link', { name: 'Catalogue' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Avis' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Revenus' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Équipe' })).toHaveCount(0);
  await expect(page.getByText('Réception', { exact: true })).toBeVisible();
});

test('staff: own planning, read-only journal, Terminé/Absent only', async ({
  page,
}) => {
  await loginAs(page, 'sonia.staff@equipe.test');
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  // The dashboard is « votre planning » — no stats, no owner cards.
  await expect(
    page.getByRole('heading', { name: 'Beauté Divine — votre planning' }),
  ).toBeVisible();
  await expect(page.getByText('À confirmer')).toHaveCount(0);
  await expect(page.getByText('Revenus ce mois')).toHaveCount(0);
  await expect(page.getByText('Configurer mon profil')).toHaveCount(0);

  // The journal: same header, the single own column, no creation.
  await page.getByRole('link', { name: 'Rendez-vous' }).click();
  await expect(
    page.getByRole('heading', { name: 'Beauté Divine — votre planning' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: '+ Nouveau rendez-vous' }),
  ).toHaveCount(0);
  await expect(page.getByText('Awa', { exact: true })).toBeVisible();
  await expect(
    page.getByRole('button', { name: /Créer un rendez-vous/ }),
  ).toHaveCount(0);

  // Their own confirmed booking: Terminé/Absent, nothing whole-journal.
  await page.goto('/pro/rendez-vous/pstaff1');
  await expect(
    page.getByRole('button', { name: 'Marquer comme terminé' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Marquer comme absent' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Client arrivé' }),
  ).toHaveCount(0);
  await expect(
    page.getByRole('button', { name: 'Reprogrammer' }),
  ).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Voir la fiche' })).toHaveCount(
    0,
  );
});

test('staff: the slim personal profil (deletion parity, no export)', async ({
  page,
}) => {
  await loginAs(page, 'sonia.staff@equipe.test');
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Profil', exact: true }).click();
  await expect(page).toHaveURL(/\/pro\/profil/);
  await expect(page.getByText('Salon : Beauté Divine')).toBeVisible();
  await expect(page.getByText('Collaborateur').first()).toBeVisible();
  // No salon editor, no export — deletion stays.
  await expect(page.getByLabel('Nom du salon')).toHaveCount(0);
  await expect(page.getByText('Exporter (JSON)')).toHaveCount(0);
  await expect(page.getByText('Supprimer mon compte')).toBeVisible();
});

test('revoked mid-session: probed out to the connexion banner', async ({
  page,
}) => {
  await loginAs(page, 'revoked.staff@equipe.test');

  // The login succeeds, but the very first membership probe 403s
  // not_a_member → sign-out → the generic banner (no salon name in the URL).
  await expect(page).toHaveURL(/\/pro\/connexion\?motif=acces-retire/);
  await expect(
    page.getByText('Votre accès à ce salon a été retiré.'),
  ).toBeVisible();
});
