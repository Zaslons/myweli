import { expect, test } from '@playwright/test';

import { signInConsumer, signInPro } from './_auth';
import { asUnaskedBrowser } from './_push';
import { serveStubImages } from './_pixel';

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


test('public: buttons, links, chips and fields all reach the floor', async ({
  page,
}) => {
  await page.goto('/');
  await assertBox(page.getByRole('button', { name: 'Rechercher' }), 'home search button', { minW: 0 });
  await assertBox(page.getByLabel('Service ou salon'), 'home search field', { minW: 0 });
  // `exact` since L1: the footer's « Supprimer mon compte » CONTAINS this name,
  // and Playwright's default substring match made a one-element assertion
  // suddenly resolve to two. The header link is what this line has always meant.
  await assertBox(
    page.getByRole('link', { name: 'Mon compte', exact: true }),
    '"Mon compte" (header)',
    { minW: 0 },
  );
  // The header logo link was 28px tall until the review measured it.
  await assertBox(page.getByRole('link', { name: 'MyWeli — accueil' }), 'header logo link', { minW: 0 });

  // L1 — the site's first <footer>. One route proves it, because it is rendered
  // from the root layout on every page: if this passes on `/` and the element
  // exists elsewhere, it is the same element.
  const footer = page.getByRole('contentinfo');
  await expect(footer).toBeVisible();
  await assertBox(
    footer.getByRole('link', { name: 'Politique de confidentialité' }),
    'footer — politique de confidentialité',
    { minW: 0 },
  );
  await assertBox(
    footer.getByRole('link', { name: 'Supprimer mon compte' }),
    'footer — suppression de compte',
    { minW: 0 },
  );

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

test('pro: « Alertes par e-mail » — the switch (salon-email-alerts)', async ({ page }) => {
  await signInPro(page);
  await page.goto('/pro/notifications');
  const sw = page.getByRole('switch', { name: 'Alertes par e-mail' });
  await expect(sw).toBeVisible();
  await assertBox(sw, '« Alertes par e-mail » switch');
});

test('pro: the browser notifications — the band’s buttons and the row’s switch (web-pro-browser-push)', async ({
  page,
}) => {
  await asUnaskedBrowser(page);
  await signInPro(page);
  for (const name of ['Activer', 'Plus tard']) {
    const b = page.getByRole('button', { name, exact: true });
    await expect(b).toBeVisible();
    await assertBox(b, `band « ${name} »`);
  }
  await page.goto('/pro/notifications');
  const sw = page.getByRole('switch', { name: 'Notifications du navigateur' });
  await expect(sw).toBeVisible();
  await assertBox(sw, '« Notifications du navigateur » switch');
});

test('pro: the deposit delay choices — each a 48px target (web-pro-deposit-app-rules)', async ({
  page,
}) => {
  await signInPro(page);
  await page.goto('/pro/acompte');
  const group = page.getByRole('radiogroup', { name: 'Politique d’annulation' });
  await expect(group).toBeVisible();
  for (const h of ['12 h', '24 h', '48 h']) {
    const choice = group.locator('label', { has: page.getByRole('radio', { name: h }) });
    await assertBox(choice, `delay choice « ${h} »`);
  }
});

test('pro: « Client sans numéro » — its whole row is the target (web-manual-booking-walk-in)', async ({
  page,
}) => {
  await signInPro(page);
  await page.goto('/pro/rendez-vous');
  await page.getByRole('button', { name: '+ Nouveau rendez-vous' }).click();
  const dialog = page.getByRole('dialog', { name: 'Nouveau rendez-vous' });
  const row = dialog.locator('label', {
    has: page.getByRole('checkbox', { name: 'Client sans numéro' }),
  });
  await expect(row).toBeVisible();
  await assertBox(row, '« Client sans numéro » row', { minW: 0 });
});

test('pro: the glyph buttons that grew invisibly', async ({ page }) => {
  await signInPro(page);

  // The hamburger (24px svg, unmoved) and the top-bar wordmark link (28px
  // before the review measured it).
  await assertBox(page.getByRole('button', { name: 'Ouvrir le menu' }), 'hamburger');
  // `exact`: the footer's « MyWeli Pro pour les salons » (web-pro-access.md
  // P2) also contains the words, and Playwright's string name is a substring.
  await assertBox(
    page.getByRole('link', { name: 'MyWeli Pro', exact: true }),
    '"MyWeli Pro" link',
    { minW: 0 },
  );

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

test('pro: the Journée’s week strip — seven days share 375px (web-pro-week-strip)', async ({
  page,
}) => {
  await signInPro(page);
  await page.goto('/pro/rendez-vous');
  const days = page.getByRole('group', { name: /^Semaine du / }).getByRole('button');
  await expect(days).toHaveCount(7);
  for (let i = 0; i < 7; i++) {
    await assertBox(days.nth(i), `week strip day ${i + 1}`);
  }
});

test('pro: the journal panel’s deposit controls (web-pro-journal-panel-deposit)', async ({
  page,
}) => {
  await serveStubImages(page);
  await signInPro(page);
  await page.goto('/pro/rendez-vous');
  await page.getByRole('button', { name: /Aminata/ }).click();
  const panel = page.getByRole('dialog', { name: 'Détails du rendez-vous' });
  // A text link in a panel full of 48px buttons — the shape that slips under
  // the floor (the panel's own « Voir la fiche » is one).
  const link = panel.getByRole('link', { name: 'Voir le rendez-vous' });
  await expect(link).toBeVisible();
  await assertBox(link, 'panel « Voir le rendez-vous »', { minW: 0 });
  // The thumbnail: 144px tall, as wide as the screenshot's own ratio — a
  // 1×1 pixel here, so 144 wide; min-w-12 holds a very tall one.
  const thumb = panel.getByRole('button', {
    name: 'Agrandir le justificatif d’acompte',
  });
  await expect(thumb).toBeVisible();
  await assertBox(thumb, 'panel deposit thumbnail');
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

/// B9 — the five tab strips, which row 7h's "0 remaining" never counted.
///
/// Each button is `px-m py-s` around a 20px line: **36px** inactive, **38px**
/// active (the `border-b-2` underline). Both are under the floor; neither
/// number is true of "every button", which is how B9's own prose first stated
/// it. Nothing measured them because this file asserts an explicit list of
/// controls and no entry named a tab — the same shape of miss as the strips'
/// overflow, in the same elements, found in the same slice.
///
/// One entry per strip, and each names the state it needs: strip #2 is behind a
/// « Liste » click, and the two-tab bars are on their own routes.
///
/// **`inactive` is not padding.** Every `tab` below names the DEFAULT-ACTIVE
/// item, so without a second locator the 36px inactive buttons — the more
/// common state, and the shorter one — are never measured in a browser at all.
/// The adversarial review caught that; the unit test's `toContain('min-h-12')`
/// was the only thing covering them, and a `sm:min-h-12` would satisfy it.
const TAB_STRIPS: {
  name: string;
  url: string;
  auth: 'pro' | 'consumer';
  tab: string;
  /// A NON-selected sibling — the 36px state.
  inactive: string;
  setup?: (page: import('@playwright/test').Page) => Promise<void>;
}[] = [
  { name: 'strip #1 — the agenda view switcher', url: '/pro/rendez-vous', auth: 'pro', tab: 'Journée', inactive: 'Calendrier' },
  {
    name: "strip #2 — the agenda's four status tabs",
    url: '/pro/rendez-vous',
    auth: 'pro',
    tab: 'Aujourd’hui',
    inactive: 'En attente',
    setup: async (page) => {
      await page.getByRole('button', { name: 'Liste' }).click();
    },
  },
  { name: 'strip #3 — catalogue', url: '/pro/catalogue', auth: 'pro', tab: 'Services', inactive: 'Employés' },
  { name: 'strip #4 — médias', url: '/pro/medias', auth: 'pro', tab: 'Photos', inactive: 'Avant / Après' },
  { name: 'strip #5 — the account booking tabs', url: '/mon-compte', auth: 'consumer', tab: 'À venir', inactive: 'Annulés' },
];

for (const strip of TAB_STRIPS) {
  test(`tabs: ${strip.name} reaches the floor`, async ({ page }) => {
    if (strip.auth === 'pro') await signInPro(page);
    else await signInConsumer(page);
    await page.goto(strip.url);
    await strip.setup?.(page);
    for (const label of [strip.tab, strip.inactive]) {
      const tab = page.getByRole('button', { name: label, exact: true }).first();
      await expect(tab, `${strip.name}: « ${label} » never rendered`).toBeVisible();
      await assertBox(tab, `${strip.name} — « ${label} »`, { minW: 0 });
    }
  });
}

/// B9's review found a SIXTH control of the same family that the class-string
/// sweep could not reach: `/pro/disponibilites`'s buffer presets, five
/// mutually-exclusive `{0,5,10,15,30} min` buttons at 38px. They escaped
/// because they already wrap — the overflow was never the thing they got wrong.
/// This route had no tap-target coverage at all.
test('the buffer presets reach the floor (§13.2)', async ({ page }) => {
  await signInPro(page);
  await page.goto('/pro/disponibilites');
  for (const label of ['0 min', '30 min']) {
    const chip = page.getByRole('button', { name: label, exact: true }).first();
    await expect(chip, `buffer preset « ${label} » never rendered`).toBeVisible();
    await assertBox(chip, `buffer preset « ${label} »`, { minW: 0 });
  }
});

/// docs/design/web-pro-week-view.md — the « Semaine » controls, at the width
/// the tab exists (desktop only).
test.describe('pro: the « Semaine » controls (web-pro-week-view)', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('‹ ›, « Cette semaine », the « Artiste » filter', async ({ page }) => {
    await signInPro(page);
    await page.goto('/pro/rendez-vous?vue=semaine');
    await expect(page.getByRole('table', { name: /^Semaine du / })).toBeVisible();
    await assertBox(page.getByRole('button', { name: 'Semaine précédente' }), '‹');
    await assertBox(page.getByRole('button', { name: 'Semaine suivante' }), '›');
    await assertBox(page.getByRole('button', { name: 'Cette semaine' }), '« Cette semaine »', { minW: 0 });
    await assertBox(page.getByLabel('Artiste', { exact: true }), '« Artiste »', { minW: 0 });
  });
});
