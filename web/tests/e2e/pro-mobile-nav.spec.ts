import { expect, test } from '@playwright/test';

/// B0 — the pro dashboard's mobile nav (WEB-SYSTEM §9). At a phone width the
/// persistent sidebar becomes an off-canvas drawer opened by a hamburger, so the
/// content is no longer crushed to ~135px by a 240px rail. Nothing tested mobile
/// before this, so nothing would have caught the bug — or a regression of it.
///
/// The rest of the pro e2e run at Playwright's default 1280px (desktop), where
/// the sidebar stays the persistent column; only this file uses a phone.
test.use({ viewport: { width: 375, height: 812 } });

async function proLogin(page: import('@playwright/test').Page) {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);
}

test('at 375px the nav is behind a hamburger, not eating the screen', async ({
  page,
}) => {
  await proLogin(page);

  // The drawer is a closed disclosure: the hamburger shows and reports shut.
  const hamburger = page.getByRole('button', { name: 'Ouvrir le menu' });
  await expect(hamburger).toBeVisible();
  await expect(hamburger).toHaveAttribute('aria-expanded', 'false');

  // The whole point of the fix: the dashboard content owns the full width — the
  // « Aujourd'hui » heading starts near the left edge, not shoved past a 240px
  // rail. (We assert the geometry, not a link's `toBeHidden`: the closed drawer
  // is translated off-screen, and a transform doesn't read as hidden.)
  const box = await page.getByRole('heading', { name: /Aujourd/ }).boundingBox();
  expect(box).not.toBeNull();
  expect(box!.x).toBeLessThan(60);

  // …and the drawer itself sits off-screen to the left. `expect.poll` retries,
  // so it waits out the 200ms slide rather than racing a one-shot boundingBox.
  await expect
    .poll(async () => {
      const b = await page.locator('#pro-sidebar-nav').boundingBox();
      return b ? b.x + b.width : 0;
    })
    .toBeLessThanOrEqual(1);
});

test('the hamburger opens the drawer; a link navigates AND closes it', async ({
  page,
}) => {
  await proLogin(page);

  await page.getByRole('button', { name: 'Ouvrir le menu' }).click();
  const clients = page.getByRole('link', { name: 'Clients' });
  await expect(clients).toBeVisible();

  await clients.click();
  await expect(page).toHaveURL(/\/pro\/clients/);
  // Close-on-navigation: the disclosure reports shut, and the drawer has slid
  // back off-screen.
  await expect(page.getByRole('button', { name: 'Ouvrir le menu' })).toHaveAttribute(
    'aria-expanded',
    'false',
  );
  await expect
    .poll(async () => {
      const b = await page.locator('#pro-sidebar-nav').boundingBox();
      return b ? b.x + b.width : 0;
    })
    .toBeLessThanOrEqual(1);
});

test('Escape and the ✕ both close the drawer', async ({ page }) => {
  await proLogin(page);
  const hamburger = page.getByRole('button', { name: 'Ouvrir le menu' });

  await hamburger.click();
  await page.keyboard.press('Escape');
  await expect(hamburger).toHaveAttribute('aria-expanded', 'false');

  await hamburger.click();
  await page.getByRole('button', { name: 'Fermer le menu' }).click();
  await expect(hamburger).toHaveAttribute('aria-expanded', 'false');
});
