import { expect, test } from '@playwright/test';

test('unauthenticated /mon-compte redirects to /connexion', async ({ page }) => {
  await page.goto('/mon-compte');
  await expect(page).toHaveURL(/\/connexion/);
  await expect(
    page.getByRole('heading', { name: 'Se connecter' }),
  ).toBeVisible();
});

test('login → see booking → open detail → cancel', async ({ page }) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  // Resend with cooldown (module 11) — counting down, disabled.
  await expect(page.getByText(/Renvoyer le code \(\d+s\)/)).toBeVisible();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();

  await expect(page).toHaveURL(/\/mon-compte/);
  await expect(
    page.getByRole('heading', { name: 'Mon compte' }),
  ).toBeVisible();

  // The enriched booking card → detail.
  await page.getByText('Beauté Divine').first().click();
  await expect(page).toHaveURL(/\/mon-compte\/appt1/);

  // Parity 1.6: contact the salon from the booking.
  await expect(page.getByRole('link', { name: 'Appeler' })).toHaveAttribute(
    'href',
    'tel:+2250700000000',
  );
  await expect(page.getByRole('link', { name: 'WhatsApp' })).toHaveAttribute(
    'href',
    'https://wa.me/2250700000000',
  );

  // P3 — the detail now mirrors the app: calendar, notes, spécialiste.
  await expect(
    page.getByRole('link', { name: 'Ajouter au calendrier (Google)' }),
  ).toHaveAttribute('href', /calendar\.google\.com/);
  await expect(page.getByRole('button', { name: 'Fichier .ics' })).toBeVisible();
  await expect(page.getByText('Cheveux fragiles')).toBeVisible();
  await expect(page.getByText('Spécialiste')).toBeVisible();
  await expect(page.locator('dd').getByText('Awa', { exact: true })).toBeVisible();

  // « Reporter » (parity 1.1): pick tomorrow's 14:00 then confirm.
  await page.getByRole('button', { name: 'Reporter', exact: true }).click();
  await page.getByRole('button', { name: '14:00' }).click();
  await page.getByRole('button', { name: 'Confirmer le report' }).click();
  await expect(page.getByText('Rendez-vous reporté ✓')).toBeVisible();

  await page.getByRole('button', { name: 'Annuler le rendez-vous' }).click();
  await page.getByRole('button', { name: /Confirmer l.annulation/ }).click();

  await expect(page.getByText('Annulé')).toBeVisible();
});

test('M8.3: rebook + review on a completed booking; favoris on /mon-compte', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // Favoris section (seeded: p1 live, p4 suspended).
  await expect(page.getByRole('heading', { name: 'Favoris' })).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Retirer des favoris' }).first(),
  ).toBeVisible();

  // Decision C: a favourite whose salon STOPPED is marked, not dropped. The
  // stub 404s `p4` on the public route — hydrating client-side would have made
  // this row vanish, and with one favourite left the page would have said
  // « Aucun favori » to someone who had two.
  await expect(page.getByText('Salon Arrêté').first()).toBeVisible();
  await expect(
    page.getByText('Ce salon ne prend plus de rendez-vous sur MyWeli.').first(),
  ).toBeVisible();
  // …and its « Retirer des favoris » stays: the one action that still helps.
  await expect(
    page.getByRole('button', { name: 'Retirer des favoris' }),
  ).toHaveCount(2);

  // Completed booking (appt2): rebook + review.
  await page.goto('/mon-compte/appt2');
  await expect(page.getByText('Terminé')).toBeVisible();
  // K2: the rebook link carries the services prefill for the hub.
  await expect(
    page.getByRole('link', { name: 'Réserver à nouveau' }),
  ).toHaveAttribute('href', '/beaute-divine/reserver?services=s1&artist=a1');

  // Leave a review — with a photo (parity 2.13).
  await page.getByRole('radio', { name: '5 étoiles' }).click();
  await page
    .locator('input[type=file]')
    .setInputFiles({
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      buffer: Buffer.from('fake-jpeg-bytes'),
    });
  await expect(page.getByAltText('Pièce jointe 1')).toBeVisible();
  await page.getByRole('button', { name: 'Envoyer l’avis' }).click();
  await expect(page.getByText(/Merci pour votre avis/)).toBeVisible();

  // Signed-in « Signaler » on the public page (parity 2.14).
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Signaler', exact: true }).click();
  await page.getByLabel('Raison du signalement').fill('Contenu déplacé');
  await page.getByRole('button', { name: 'Signaler', exact: true }).click();
  await expect(
    page.getByText('Merci. Notre équipe va examiner cet avis.'),
  ).toBeVisible();
});

test('M8.3: provider favorite toggle → /connexion when signed out', async ({
  page,
}) => {
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Ajouter aux favoris' }).click();
  await expect(page).toHaveURL(/\/connexion/);
});

test('Confidentialité : export des données + suppression type-SUPPRIMER (11.1/11.2)', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // Name edit (11.3).
  await page.getByRole('button', { name: 'Modifier le nom' }).click();
  await page.getByLabel('Nom').fill('Awa K.');
  await page.getByRole('button', { name: 'OK', exact: true }).click();
  await expect(page.getByText('Awa K.')).toBeVisible();

  // Export page (11.2): counts + download/copy actions.
  await page.getByRole('link', { name: 'Exporter mes données' }).click();
  await expect(page).toHaveURL(/\/mon-compte\/donnees/);
  await expect(
    page.getByRole('heading', { name: 'Mes données' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Télécharger (JSON)' }),
  ).toBeVisible();
  await page.getByRole('link', { name: '← Mon compte' }).click();

  // Deletion (11.1): gated on typing SUPPRIMER, then home + signed out.
  await page.getByRole('button', { name: 'Supprimer mon compte' }).click();
  const confirm = page.getByRole('button', { name: 'Supprimer définitivement' });
  await expect(confirm).toBeDisabled();
  await page.getByLabel('Confirmation de suppression').fill('SUPPRIMER');
  await confirm.click();
  await expect(page).toHaveURL(/\/$/);
});

test('notifications: center + Tout lire + préférence (parity 5.1/5.2)', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // Entry point from the account page.
  await page.getByRole('link', { name: 'Notifications' }).click();
  await expect(page).toHaveURL(/\/mon-compte\/notifications/);

  // The unread item shows; « Tout lire » clears the unread state.
  await expect(page.getByText('Rendez-vous confirmé')).toBeVisible();
  await expect(page.getByText('Bienvenue sur MyWeli')).toBeVisible();
  await page.getByRole('button', { name: 'Tout lire' }).click();
  await expect(page.getByRole('button', { name: 'Tout lire' })).toBeHidden();

  // Préférences: toggle marketing off (optimistic, stub-persisted).
  const marketing = page.getByRole('switch', { name: 'Offres & promotions' });
  await expect(marketing).toHaveAttribute('aria-checked', 'true');
  await marketing.click();
  await expect(marketing).toHaveAttribute('aria-checked', 'false');
});

test('P3 extras: proof view, salon visits card, search hearts, support', async ({
  page,
}) => {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  // 15.2 — the support entry.
  //
  // It used to assert a `wa.me` href, which only ever passed because
  // playwright.config.ts sets a dummy NEXT_PUBLIC_MYWELI_WHATSAPP. No real
  // build sets that variable, so in production the row did not render at all —
  // the e2e was green on a configuration no user has ever had.
  await expect(
    page.getByRole('link', { name: 'Aide & Support' }),
  ).toHaveAttribute('href', '/support');

  // 1.3 — « Voir ma capture » on the pending booking with an attached proof.
  await page.goto('/mon-compte/appt3');
  await expect(
    page.getByRole('link', { name: 'Voir ma capture' }),
  ).toHaveAttribute(
    'href',
    '/api/appointments/appt3/deposit-screenshot?redirect=1',
  );

  // 2.7/2.8 — the personal section on the salon page.
  await page.goto('/beaute-divine');
  await expect(page.getByText('Vos rendez-vous ici')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Voir tout' })).toHaveAttribute(
    'href',
    '/mon-compte',
  );
  await expect(
    page.getByRole('link', { name: 'Donner votre avis' }),
  ).toHaveAttribute('href', '/mon-compte/appt2');

  // 2.15 — hearts on the /recherche cards (signed-in toggle).
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
  await page.goto('/recherche?q=tresses');
  const heart = page.getByRole('button', {
    name: /Ajouter Beauté Divine aux favoris|Retirer Beauté Divine des favoris/,
  });
  await expect(heart).toBeVisible();
  // Two waits, both load-bearing, neither a timeout bump.
  //
  // FIRST: the heart is disabled until `/api/me/favorites` has answered.
  // Before that the card cannot know whether you are signed in — and clicking
  // during the window used to navigate a signed-in visitor to /connexion,
  // because `favIds === null` meant both "loading" and "anonymous". Waiting for
  // enabled is waiting for the component to know.
  await expect(heart).toBeEnabled();
  const before = await heart.getAttribute('aria-pressed');
  // SECOND: the toggle is NOT optimistic — `RechercheClient` only calls
  // `setFavIds` after the write resolves, which is the honest choice (it never
  // shows a state the server has not accepted). So the assertion has to wait
  // for the write, not for a re-render that has not been scheduled yet. Under
  // CI load that round-trip outran the default timeout, which is the whole of
  // the flake.
  const written = page.waitForResponse(
    (r) =>
      /\/api\/me\/favorites\//.test(r.url()) &&
      ['POST', 'DELETE'].includes(r.request().method()),
  );
  await heart.click();
  await written;
  await expect(heart).toHaveAttribute(
    'aria-pressed',
    before === 'true' ? 'false' : 'true',
  );
});

test('a signed-in visitor clicking a heart before favourites load is NOT sent to login', async ({
  page,
}) => {
  // The bug behind the flake, forced instead of raced.
  //
  // `favIds === null` meant BOTH "still asking" and "anonymous", and
  // `toggleFavorite` read it as the second — so clicking a heart during the
  // window between page load and `/api/me/favorites` answering navigated a
  // SIGNED-IN visitor to /connexion. Locally that window is a few milliseconds;
  // on a slow connection it is not, and in CI it was long enough to make
  // `P3 extras` fail.
  //
  // Holding the GET open makes the window arbitrarily wide, so this fails
  // deterministically without the fix rather than once in twenty runs.
  // Signed in the same way every other test in this file does.
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());

  let release = () => {};
  const held = new Promise<void>((r) => {
    release = r;
  });
  await page.route('**/api/me/favorites', async (route) => {
    if (route.request().method() === 'GET') await held;
    await route.continue();
  });

  await page.goto('/recherche?q=tresses');
  const heart = page.getByRole('button', {
    name: /Ajouter Beauté Divine aux favoris|Retirer Beauté Divine des favoris/,
  });
  await expect(heart).toBeVisible();

  // While the answer is unknown the control must not look ready.
  await expect(heart, 'the heart is live while it cannot know who you are').toBeDisabled();

  // `RechercheClient.toggleFavorite` also returns early while `!favLoaded`.
  // NOT asserted here, deliberately: the browser dispatches no click on a
  // disabled button — not even `click({ force: true })` — so that guard is
  // unreachable through the DOM while `disabled` is in place, and a test for it
  // would pass no matter what the guard did. Removing `disabled` turns this
  // test red; removing the guard alone does not, and pretending otherwise
  // would be exactly the vacuous check this suite keeps deleting. The guard
  // stays as an invariant of the function for non-DOM callers.

  release();
  await expect(heart).toBeEnabled();

  const before = await heart.getAttribute('aria-pressed');
  const written = page.waitForResponse(
    (r) =>
      /\/api\/me\/favorites\//.test(r.url()) &&
      ['POST', 'DELETE'].includes(r.request().method()),
  );
  await heart.click();
  await written;

  await expect(page, 'a signed-in visitor was sent to the login page').not.toHaveURL(
    /\/connexion/,
  );
  await expect(heart).toHaveAttribute(
    'aria-pressed',
    before === 'true' ? 'false' : 'true',
  );
});

test('a booking at a salon that stopped keeps working, and says why', async ({
  page,
}) => {
  // The case the whole slice exists for. `p4` is suspended and the stub 404s
  // it on the PUBLIC route — exactly what Decision C will do — so everything
  // asserted here is served by the authenticated read that owns the
  // relationship.
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill('awa@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/mon-compte/);

  await page.goto('/mon-compte/appt5');

  // The salon's identity survives the public route closing.
  await expect(
    page.getByRole('heading', { name: 'Salon Arrêté' }),
  ).toBeVisible();
  await expect(
    page.getByText('Ce salon ne prend plus de rendez-vous sur MyWeli.'),
  ).toBeVisible();

  // Withheld: the move the server would refuse, and the link that would 404.
  await expect(page.getByRole('button', { name: 'Reporter' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Voir le salon' })).toHaveCount(
    0,
  );

  // Kept: cancelling (never trap a client in a booking) and the contact
  // details (this is when they need the salon most). Both used to VANISH here,
  // with the app blaming the phone number for a salon-state problem.
  await expect(
    page.getByRole('button', { name: 'Annuler le rendez-vous' }),
  ).toBeVisible();
  await expect(page.getByRole('link', { name: 'Appeler' })).toHaveAttribute(
    'href',
    'tel:+2250700000000',
  );
});
