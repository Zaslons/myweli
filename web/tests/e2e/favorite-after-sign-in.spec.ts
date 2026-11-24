import { expect, test, type Page } from '@playwright/test';
import { CONSUMER_EMAIL, submitOtpLogin } from './_auth';

/// A3w (docs/design/consumer-signin-push.md §14, decision 205): a heart a
/// guest taps is applied once they are back from the sign-in it opened — on
/// the salon page and on the search's cards — and `/connexion` says why.
///
/// The stub's favourites always hold `p1` (Beauté Divine). For the « added »
/// path the signed-in read is answered empty here, so the add is what the
/// page decides, not what the stub happens to hold.

const REASON = 'Connectez-vous pour ajouter ce salon à vos favoris.';

/// The signed-in favourites read, answered empty; a guest's 401 passes as is.
async function noFavouritesYet(page: Page) {
  await page.route('**/api/me/favorites', async (route) => {
    const real = await route.fetch();
    if (real.status() !== 200) return route.fulfill({ response: real });
    return route.fulfill({ status: 200, json: { favorites: [] } });
  });
}

/// The favourites writes sent from now on.
function countWrites(page: Page) {
  const writes: string[] = [];
  page.on('request', (r) => {
    if (/\/api\/me\/favorites\/[^/?]+/.test(r.url()) && r.method() !== 'GET') {
      writes.push(`${r.method()} ${new URL(r.url()).pathname}`);
    }
  });
  return writes;
}

/// The page's favourites read after the sign-in — registered BEFORE it, and
/// awaited before any « nothing happened » is believed. The return is a soft
/// navigation (`router.replace`): `waitForLoadState` answers at once there,
/// and would have let an assertion run before the read had answered.
function nextFavouritesRead(page: Page) {
  return page.waitForResponse(
    (r) => new URL(r.url()).pathname === '/api/me/favorites' && r.request().method() === 'GET',
  );
}

/// The e-mail step, typed again until the code step opens. The search's heart
/// leaves by a full page load (`window.location.assign`), and `toHaveURL`
/// passes before that page is hydrated: an e-mail typed then was lost, and
/// « Continuer avec e-mail » did nothing — 6 runs in 8 locally. The salon's
/// heart leaves by a client navigation, on a page already hydrated. The
/// sign-in itself is not what this spec tests (`_auth.ts`'s helper expects a
/// page reached by `page.goto`, which waits for its load).
async function submitEmailLogin(page: Page) {
  const code = page.getByLabel('Code à 6 chiffres');
  await expect(async () => {
    await page.getByLabel('Votre e-mail').fill(CONSUMER_EMAIL);
    await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
    await expect(code).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 15_000 });
  await code.fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
}

/// The guest is on /connexion with the reason, and signs in there. Resolves
/// once the page they return to has read its favourites, with the writes sent
/// since the sign-in began — counted from BEFORE it, so a write decided the
/// instant the read answers cannot slip past the counter. The guest's own
/// tap (a 401 on the salon page) is over by then: it is what opened this page.
async function signInFromTheHeart(page: Page) {
  await expect(page).toHaveURL(/\/connexion\?raison=favori&returnTo=/);
  await expect(page.getByText(REASON)).toBeVisible();
  const writes = countWrites(page);
  const read = nextFavouritesRead(page);
  await submitEmailLogin(page);
  await read;
  return writes;
}

test('the salon page: a guest’s heart is added once they are back, with « Annuler »', async ({
  page,
}) => {
  await noFavouritesYet(page);
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Ajouter aux favoris' }).click();
  const writes = await signInFromTheHeart(page);

  // Back on the salon, the marker gone from the address.
  await expect(page).toHaveURL(/\/beaute-divine$/);
  await expect(page.getByText('Ajouté aux favoris')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Annuler' })).toBeVisible();
  await expect(page.getByRole('button', { name: /Favori/ })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  expect(writes).toEqual(['POST /api/me/favorites/p1']);
});

test('the salon page: already a favourite — « Déjà dans vos favoris », nothing sent', async ({
  page,
}) => {
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Ajouter aux favoris' }).click();
  const writes = await signInFromTheHeart(page);

  await expect(page).toHaveURL(/\/beaute-divine$/);
  await expect(page.getByText('Déjà dans vos favoris')).toBeVisible();
  await expect(page.getByRole('button', { name: /Favori/ })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  // The read has answered (awaited above) and the page has said what it
  // decided: a write, had it been decided, would have gone with it.
  expect(writes).toEqual([]);
});

test('the search: a guest’s heart is added once they are back on the same search', async ({
  page,
}) => {
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
  await noFavouritesYet(page);
  await page.goto('/recherche?q=tresses');
  const heart = page.getByRole('button', { name: 'Ajouter Beauté Divine aux favoris' });
  await expect(heart).toBeEnabled();
  await heart.click();
  const writes = await signInFromTheHeart(page);

  await expect(page).toHaveURL(/\/recherche\?q=tresses$/);
  await expect(page.getByText('Ajouté aux favoris')).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Retirer Beauté Divine des favoris' }),
  ).toHaveAttribute('aria-pressed', 'true');
  expect(writes).toEqual(['POST /api/me/favorites/p1']);
});

test('CONTROL — a heart stored, then a sign-in opened another way: no reason, nothing applied', async ({
  page,
}) => {
  await noFavouritesYet(page);
  // The heart is stored in this tab…
  await page.goto('/beaute-divine');
  await page.getByRole('button', { name: 'Ajouter aux favoris' }).click();
  await expect(page).toHaveURL(/\/connexion\?raison=favori&returnTo=/);
  // …but the sign-in that follows is not the one it opened (no marker back).
  await page.goto('/connexion?returnTo=%2Fbeaute-divine');
  await expect(page.getByText(REASON)).toHaveCount(0);
  const writes = countWrites(page);
  const read = nextFavouritesRead(page);
  await submitOtpLogin(page, CONSUMER_EMAIL);
  await read;
  await expect(page).toHaveURL(/\/beaute-divine$/);
  await expect(page.getByRole('button', { name: 'Ajouter aux favoris' })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Ajouter aux favoris' })).toHaveAttribute(
    'aria-pressed',
    'false',
  );
  await expect(page.getByText('Ajouté aux favoris')).toHaveCount(0);
  expect(writes).toEqual([]);
});
