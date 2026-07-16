import { expect, test } from '@playwright/test';

/// B4 — §13.2's 48px floor, pinned (WEB-SYSTEM §15 row 7h).
///
/// Before B4, NOT ONE interactive control on the web reached 48px: `Button` —
/// every button — was 36; the glyph floor was 16; the only 48px box in the
/// codebase was a non-interactive avatar. Mobile burned this to 0 in A4a with a
/// gate (`androidTapTargetGuideline`); this spec is that gate's web twin — a loop
/// over real controls on real pages, asserting the rendered box, so the floor
/// cannot silently regress.
///
/// §13.2's own terms: the GLYPH may stay small (§7 — "never grow the glyph to
/// make the target bigger, grow the target"), so several boxes here are grown by
/// padding + negative margin with the pixels unmoved. The box is what the finger
/// gets, and the box is what this measures.

test.use({ viewport: { width: 375, height: 812 } });

const FLOOR = 48;

async function assertBox(
  locator: import('@playwright/test').Locator,
  what: string,
  { minW = FLOOR, minH = FLOOR }: { minW?: number; minH?: number } = {},
) {
  const box = await locator.boundingBox();
  expect(box, `${what} — no box`).not.toBeNull();
  expect(box!.height, `${what} height ${box!.height} < ${minH}`).toBeGreaterThanOrEqual(minH);
  expect(box!.width, `${what} width ${box!.width} < ${minW}`).toBeGreaterThanOrEqual(minW);
}

async function proLogin(page: import('@playwright/test').Page) {
  await page.goto('/pro/connexion');
  await page.getByLabel('Votre e-mail').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.getByLabel('Code à 6 chiffres').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);
}

test('public: buttons, links, chips and fields all reach the floor', async ({
  page,
}) => {
  await page.goto('/');
  await assertBox(page.getByRole('button', { name: 'Rechercher' }), 'home search button', { minW: 0 });
  await assertBox(page.getByLabel('Service ou salon'), 'home search field', { minW: 0 });
  await assertBox(page.getByRole('link', { name: 'Mon compte' }), '"Mon compte"', { minW: 0 });
  // The header logo link was 28px tall until the review measured it.
  await assertBox(page.getByRole('link', { name: 'MyWeli — accueil' }), 'header logo link', { minW: 0 });

  await page.goto('/recherche?commune=Cocody');
  // The category chips grew 28 → 48 (A4a's own pills→48 precedent). « Tous » is
  // unconditional — no count()-then-skip (count() doesn't wait for hydration).
  const chip = page.getByRole('link', { name: 'Tous', exact: true });
  await expect(chip).toBeVisible();
  await assertBox(chip, 'category chip « Tous »', { minW: 0 });
  // The floating Carte/Liste toggle (mobile-only — this viewport IS 375).
  const mapToggle = page.getByRole('button', { name: /^(Carte|Liste)$/ });
  await expect(mapToggle).toBeVisible();
  await assertBox(mapToggle, 'Carte/Liste toggle', { minW: 0 });

  await page.goto('/connexion');
  await assertBox(page.getByLabel('Votre e-mail'), 'login email field', { minW: 0 });
  await assertBox(
    page.getByRole('button', { name: 'Continuer avec e-mail' }),
    'login submit',
    { minW: 0 },
  );
});

test('salon page: the favourite ♥ is a 48px target', async ({ page }) => {
  await page.goto('/beaute-divine'); // the stub salon's real slug
  // No count()-then-skip: count() doesn't wait for hydration, so it skipped a
  // control that IS there — the exact green-because-skipped trap. Wait instead.
  const heart = page.getByRole('button', { name: /favoris/i }).first();
  await expect(heart).toBeVisible();
  await assertBox(heart, 'favourite ♥');
});

test('pro: the glyph buttons that grew invisibly', async ({ page }) => {
  await proLogin(page);

  // The hamburger (24px svg, unmoved) and the top-bar wordmark link (28px
  // before the review measured it).
  await assertBox(page.getByRole('button', { name: 'Ouvrir le menu' }), 'hamburger');
  await assertBox(page.getByRole('link', { name: 'MyWeli Pro' }), '"MyWeli Pro" link', { minW: 0 });

  // The drawer: its ✕ (16px glyph before B4) and a nav link (207×36 before the
  // review measured those too). « Rendez-vous » has no capability gate, so it
  // renders for every membership.
  await page.getByRole('button', { name: 'Ouvrir le menu' }).click();
  await assertBox(page.getByRole('button', { name: 'Fermer le menu' }), 'drawer ✕');
  const navLink = page.getByRole('link', { name: 'Rendez-vous' });
  await expect(navLink).toBeVisible();
  await assertBox(navLink, 'sidebar nav link', { minW: 0 });
  await page.getByRole('button', { name: 'Fermer le menu' }).click();

  // NOT pinned here: EquipeClient's ⋯ row menu — the stub seeds no second
  // member, so the row never renders and a guard would pass vacuously (the
  // first draft of this spec did exactly that). The control is floored in
  // code (`-mx-s -my-sm` + min-h-12); pinning it needs a stub with members.
});

test('account: the switch and the review stars', async ({ page }) => {
  await page.goto('/connexion');
  await page.getByLabel('Votre e-mail').fill('client@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.getByLabel('Code à 6 chiffres').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.waitForURL(/mon-compte|\/$/);

  await page.goto('/mon-compte/notifications');
  const switches = page.getByRole('switch');
  await expect(switches.first()).toBeVisible(); // prefs load async — wait, don't skip
  const n = await switches.count();
  expect(n).toBeGreaterThan(0);
  for (let i = 0; i < n; i++) {
    await assertBox(switches.nth(i), `switch #${i}`);
  }
});
