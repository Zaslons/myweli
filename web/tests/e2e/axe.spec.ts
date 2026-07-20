import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

/// B5 — §14's "the whole of §4–§8, on real pages" gate (WEB-SYSTEM §15 row 15).
///
/// axe-core over 15 real routes (public + consumer + pro, stub-seeded), plus
/// two STATEFUL scans — an open Modal and a visible Toast — because a dialog
/// that only exists after a click never appears in a route-level crawl.
///
/// Proof-red (branch base 479e092, MEASURED — scratchpad/axe-base.json):
/// **11 violations · 13 nodes · 5 rules · 8 of 12 routes red.**
/// - `region` (moderate) on 7 routes — the home hero (h1 + search, 5 nodes)
///   sat OUTSIDE <main>, and the AppInstallBanner was landmark-less chrome on
///   every consumer page. Nothing in the register knew either.
/// - `heading-order` on /recherche — the registered row-14 skip.
/// - `nested-interactive` (serious) on /recherche — maplibre stamps
///   role="button" on its marker wrapper AROUND our named pin button. NEW.
/// - `aria-prohibited-attr` (serious) on /beaute-divine — MapEmbed's
///   aria-label on a role-less div. NEW.
/// - `empty-table-header` on /pro/equipe — the actions column. NEW.
/// The row-21 radiogroup never fired at base because the stars live on
/// /mon-compte/[id] — which the first matrix DIDN'T visit. It does now
/// (13th route, the stub's appt2), so the fix is pinned, not assumed.
///
/// No rule exclusions. If one ever becomes unavoidable (third-party
/// internals), it gets a ds-ignore-style prose reason HERE, per finding —
/// fix first, exclude last.

test.beforeEach(async ({ page }) => {
  // Hermetic like every other map spec: live basemap traffic both stalls
  // networkidle on CI and makes the scanned DOM depend on CDN reachability.
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
});

async function expectNoViolations(
  page: import('@playwright/test').Page,
  where: string,
) {
  const results = await new AxeBuilder({ page }).analyze();
  const readable = results.violations.map((v) => ({
    rule: v.id,
    impact: v.impact,
    targets: v.nodes.slice(0, 5).map((n) => n.target.join(' ')),
  }));
  expect(readable, `${where}: axe violations`).toEqual([]);
}

async function login(page: import('@playwright/test').Page, email: string) {
  await page.getByLabel('Votre e-mail').fill(email);
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.getByLabel('Code à 6 chiffres').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
}

test('public routes are axe-clean', async ({ page }) => {
  for (const route of [
    '/',
    '/recherche?commune=Cocody',
    '/beaute-divine',
    '/beaute-divine/reserver',
    '/connexion',
    '/pro/connexion',
    // The review's finds: an AREA taxonomy landing (its h1→h3 skip survived
    // the first matrix) — landing.spec's own stub route.
    '/coiffure/abidjan/cocody',
  ]) {
    await page.goto(route);
    await page.waitForLoadState('networkidle');
    await expectNoViolations(page, route);
  }
});

test('consumer account routes are axe-clean', async ({ page }) => {
  await page.goto('/connexion');
  await login(page, 'client@example.com');
  await page.waitForURL(/mon-compte|\/$/);
  for (const route of ['/mon-compte', '/mon-compte/notifications', '/mon-compte/appt2']) {
    await page.goto(route);
    await page.waitForLoadState('networkidle');
    await expectNoViolations(page, route);
  }
});

test('pro routes are axe-clean', async ({ page }) => {
  await page.goto('/pro/connexion');
  await login(page, 'salon@example.com');
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  for (const route of ['/pro', '/pro/rendez-vous', '/pro/equipe', '/pro/clients', '/pro/apercu']) {
    await page.goto(route);
    await page.waitForLoadState('networkidle');
    await expectNoViolations(page, route);
  }
});

test('an OPEN dialog is axe-clean (the stateful scan a crawl never sees)', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await login(page, 'salon@example.com');
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await page.goto('/pro/clients');
  await page.getByRole('button', { name: 'Ajouter un client' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expectNoViolations(page, '/pro/clients + add-client Modal');
});

test('a VISIBLE toast is axe-clean', async ({ page }) => {
  await page.goto('/pro/connexion');
  await login(page, 'salon@example.com');
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await page.goto('/pro/rendez-vous');
  // The SUCCESS toast (« Rendez-vous créé ») — the review moved in-dialog
  // errors INSIDE the aria-modal subtree, so the toast path is a completed
  // creation (deterministic against the stub; pro.spec's own recipe).
  await page.getByRole('button', { name: '+ Nouveau rendez-vous' }).click();
  const dialog = page.getByRole('dialog', { name: 'Nouveau rendez-vous' });
  await dialog.getByRole('checkbox').first().check();
  await dialog.getByLabel('Rechercher ou nommer le client').fill('Cliente Axe');
  await dialog.getByLabel('Date du rendez-vous').fill('2026-12-01');
  await dialog.getByLabel('Heure du rendez-vous').fill('09:00');
  await dialog.getByRole('button', { name: 'Créer', exact: true }).click();
  const toast = page.getByRole('status').filter({ hasText: /./ });
  await expect(toast).toBeVisible();
  await expectNoViolations(page, '/pro/rendez-vous + toast');
  // The scan is only proof if the toast SURVIVED it (success auto-dismisses
  // at 3 s — an expired pill would make this scan silently vacuous).
  await expect(toast).toBeVisible();
});
