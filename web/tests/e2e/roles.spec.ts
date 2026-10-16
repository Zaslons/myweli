import AxeBuilder from '@axe-core/playwright';
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
  await expect(page.getByText('Demandes en attente')).toBeVisible();
  await expect(page.getByText(/^Revenus prévus/)).toHaveCount(0);
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
    // Rename-tolerant: pro.spec's profil journey renames the shared stub
    // salon to « Beauté Divine Web » — worker scheduling decides the order.
    page.getByRole('heading', { name: /Beauté Divine( Web)? — votre planning/ }),
  ).toBeVisible();
  await expect(page.getByText('Demandes en attente')).toHaveCount(0);
  await expect(page.getByText(/^Revenus prévus/)).toHaveCount(0);
  await expect(page.getByText('Configurer mon profil')).toHaveCount(0);

  // The journal: same header, the single own column, no creation.
  await page.getByRole('link', { name: 'Rendez-vous' }).click();
  await expect(
    // Rename-tolerant: pro.spec's profil journey renames the shared stub
    // salon to « Beauté Divine Web » — worker scheduling decides the order.
    page.getByRole('heading', { name: /Beauté Divine( Web)? — votre planning/ }),
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

test('manager: the full profil editor, without the export (the owner\'s, as in the app)', async ({
  page,
}) => {
  // docs/design/web-pro-export-completeness.md §6 — the export gate is
  // salon.publish, the app's; profile.manage alone (the Manager) edits the
  // salon but does not take its data out.
  await loginAs(page, 'awa.manager@equipe.test');
  await expect(page).toHaveURL(/\/pro(\/)?$/);

  await page.getByRole('link', { name: 'Profil', exact: true }).click();
  await expect(page).toHaveURL(/\/pro\/profil/);
  await expect(page.getByLabel('Nom du salon')).toBeVisible();
  await expect(page.getByText('Exporter (JSON)')).toHaveCount(0);
  await expect(
    page.getByRole('button', { name: 'Supprimer mon compte' }),
  ).toBeVisible();
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
  // Role-scoped since L1: the site footer now links « Supprimer mon compte »
  // on every page including /pro, so a bare text match resolves to two. The
  // danger-zone BUTTON is what this line has always meant.
  await expect(
    page.getByRole('button', { name: 'Supprimer mon compte' }),
  ).toBeVisible();
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

// --- the rejoin gate (docs/design/pro-rejoin-gate.md) ----------------------
// A former member — revoked, then re-invited — logs in. The session is live
// but every probe answers not_a_member, so before signing out the web asks
// for the account's own invitations: one is pending, so the « Invitations »
// page replaces the dashboard instead of the banner. The stub's two
// former-member fixtures re-arm at each login and sit outside the Équipe
// roster (team.spec's seat counts never move).

test('a re-invited former member joins from « Invitations » and lands on '
  + 'their planning', async ({ page }) => {
  await loginAs(page, 'ancien.rejoint@equipe.test');

  await expect(
    page.getByRole('heading', { level: 1, name: 'Invitations' }),
  ).toBeVisible();
  await expect(page.getByText(/vous\s+invite comme Collaborateur/)).toBeVisible();
  // Nothing of a salon is reachable from here: no sidebar, no drawer.
  await expect(page.getByRole('link', { name: 'Rendez-vous' })).toHaveCount(0);
  await expect(
    page.getByRole('button', { name: 'Ouvrir le menu' }),
  ).toHaveCount(0);
  await expect(page).not.toHaveURL(/motif=acces-retire/);

  await page.getByRole('button', { name: 'Rejoindre' }).click();

  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await expect(
    // Rename-tolerant: pro.spec's profil journey renames the shared stub
    // salon to « Beauté Divine Web » — worker scheduling decides the order.
    page.getByRole('heading', { name: /Beauté Divine( Web)? — votre planning/ }),
  ).toBeVisible();
  await expect(
    page.getByText(/^Vous avez rejoint Beauté Divine( Web)?$/),
  ).toBeVisible();
  // The identity block: the member's own address, in the joined salon.
  await expect(page.getByText('ancien.rejoint@equipe.test')).toBeVisible();
});

test('a re-invited former member who declines is signed out onto the banner', async ({
  page,
}) => {
  // The narrowest phone the system designs for: the gate must reflow there.
  await page.setViewportSize({ width: 320, height: 640 });
  await loginAs(page, 'ancien.refus@equipe.test');

  await expect(
    page.getByRole('heading', { level: 1, name: 'Invitations' }),
  ).toBeVisible();
  await expect(page.getByText(/vous\s+invite comme Réception/)).toBeVisible();

  // Accessibility is part of the page (WEB-SYSTEM §4–§8, SYSTEM §13.2): axe
  // clean as rendered, and every control a full 48px target.
  const axe = await new AxeBuilder({ page }).analyze();
  expect(
    axe.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target).join(', ')}`),
    'the rejoin gate: axe violations',
  ).toEqual([]);
  for (const name of ['Rejoindre', 'Refuser', 'Se déconnecter']) {
    const box = await page.getByRole('button', { name }).boundingBox();
    expect(box?.height, `${name}: tap target height`).toBeGreaterThanOrEqual(48);
  }
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow, 'horizontal scroll at 320px').toBeLessThanOrEqual(0);

  await page.getByRole('button', { name: 'Refuser' }).click();

  await expect(page).toHaveURL(/\/pro\/connexion\?motif=acces-retire/);
  await expect(
    page.getByText('Votre accès à ce salon a été retiré.'),
  ).toBeVisible();
});
