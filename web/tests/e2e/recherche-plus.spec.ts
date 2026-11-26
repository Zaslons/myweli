import { expect, test } from '@playwright/test';

/// docs/design/consumer-search.md §3.3 (A4w, decision 233): on `/recherche` the count is the
/// server's `total`, « Afficher plus de salons » reads the next 24 through the same-origin
/// route and appends them, its failure keeps the rows, and the address keeps the pages read
/// so a reload — and « Retour » — show the same rows. The stub pages thirty salons
/// (`q=nombreux`) and refuses the second page of `q=suite-echoue`.

const rows = (page: import('@playwright/test').Page) =>
  page.getByRole('heading', { level: 3, name: /^Salon Nombreux / });

test.beforeEach(async ({ page }) => {
  // goto waits for `load` — abort tiles or slow CARTO fetches stall CI.
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
});

test('the count is the server’s total; « Afficher plus » appends the rest and goes', async ({
  page,
}) => {
  await page.goto('/recherche?q=nombreux');
  await expect(page.getByRole('heading', { level: 2, name: '30 salons' })).toBeVisible();
  await expect(rows(page)).toHaveCount(24);

  const more = page.getByRole('button', { name: 'Afficher plus de salons' });
  const read = page.waitForRequest((r) => r.url().includes('/api/recherche'));
  await more.click();
  const asked = new URL((await read).url());
  expect(asked.searchParams.get('q')).toBe('nombreux');
  expect(asked.searchParams.get('page')).toBe('2');

  await expect(rows(page)).toHaveCount(30);
  await expect(more).toHaveCount(0);
  // The keyboard continues where the new rows start.
  await expect(page.getByRole('link', { name: /Salon Nombreux 25/ })).toBeFocused();
  await expect(page).toHaveURL(/[?&]pages=2(&|$)/);
});

test('a reload shows the same thirty', async ({ page }) => {
  await page.goto('/recherche?q=nombreux');
  await page.getByRole('button', { name: 'Afficher plus de salons' }).click();
  await expect(rows(page)).toHaveCount(30);

  await page.reload();
  await expect(rows(page)).toHaveCount(30);
  await expect(page.getByRole('button', { name: 'Afficher plus de salons' })).toHaveCount(0);
});

test('« Retour » from a salon shows the same thirty — no reload between', async ({ page }) => {
  await page.goto('/recherche?q=nombreux');
  await page.getByRole('button', { name: 'Afficher plus de salons' }).click();
  await expect(rows(page)).toHaveCount(30);

  // A card is a plain link: the salon is a document of its own (here the stub's salon has no
  // page, so it is the 404 — a document all the same).
  await page.getByRole('link', { name: /Salon Nombreux 27/ }).click();
  await expect(page).not.toHaveURL(/\/recherche/);
  await page.goBack();
  await expect(page).toHaveURL(/[?&]pages=2(&|$)/);
  await expect(rows(page)).toHaveCount(30);
});

test('« Retour » after a search from the header: the address and the rows agree', async ({
  page,
}) => {
  await page.goto('/recherche?q=nombreux');
  await page.getByRole('button', { name: 'Afficher plus de salons' }).click();
  await expect(rows(page)).toHaveCount(30);
  await expect(page).toHaveURL(/[?&]pages=2(&|$)/);

  // The header's search navigates in place (`router.push`): no document load.
  const field = page.getByLabel('Service ou salon');
  await field.fill('vide');
  await field.press('Enter');
  await expect(page).toHaveURL(/\/recherche\?q=vide$/);

  await page.goBack();
  await expect(page).toHaveURL(/q=nombreux/);
  // Next may give back its own copy of the first answer (24 rows), or ask the server again
  // with pages=2 (30). Either way, the address says what is shown.
  await expect(rows(page).first()).toBeVisible();
  await expect
    .poll(async () => {
      const n = await rows(page).count();
      const pages = new URL(page.url()).searchParams.get('pages');
      return n === 30 ? pages === '2' : n === 24 ? pages === null : false;
    })
    .toBe(true);
});

test('a failed page: « Impossible d’afficher la suite. », the rows kept, « Réessayer » focused', async ({
  page,
}) => {
  await page.goto('/recherche?q=suite-echoue');
  await expect(page.getByRole('heading', { level: 2, name: '30 salons' })).toBeVisible();
  await page.getByRole('button', { name: 'Afficher plus de salons' }).click();
  await expect(page.getByText('Impossible d’afficher la suite.')).toBeVisible();
  await expect(rows(page)).toHaveCount(24);
  await expect(page.getByRole('button', { name: 'Réessayer' })).toBeFocused();
  await expect(page).not.toHaveURL(/pages=/);
});

test('the map shows a pin for every row, the appended ones too', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/recherche?q=nombreux');
  const pins = page.locator('.myweli-marker');
  await expect(pins).toHaveCount(24);
  await page.getByRole('button', { name: 'Afficher plus de salons' }).click();
  await expect(rows(page)).toHaveCount(30);
  await expect(pins).toHaveCount(30);
});
