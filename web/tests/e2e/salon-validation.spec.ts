import AxeBuilder from '@axe-core/playwright';
import { type APIRequestContext, type Page, expect, test } from '@playwright/test';

import { signInPro } from './_auth';

/// B0.18 on the website — docs/design/web-salon-validation.md §7 (parent:
/// salon-go-live-approval.md §8.4). The stub is a B0.18 server; `POST
/// /__stub/validation` stands in for the admin. These journeys run on their
/// OWN identity and salon (`pv1`, « Salon Validation »), so no other spec sees
/// a salon refused or taken live while workers share the stub; serial, and the
/// salon is reset before and after.

const STUB = `http://127.0.0.1:${process.env.STUB_PORT ?? '8787'}`;
const OWNER = 'validation.salon@salon.test';
const SALON = 'pv1';

async function admin(request: APIRequestContext, body: Record<string, unknown>) {
  const res = await request.post(`${STUB}/__stub/validation`, { data: { salonId: SALON, ...body } });
  expect(res.ok(), JSON.stringify(body)).toBe(true);
}

/// The card is drawn once its checklist read has landed.
async function cardReady(page: Page) {
  await expect(page.getByRole('progressbar', { name: /étapes? sur \d+ terminées?/ })).toBeVisible();
}

async function expectAxeClean(page: Page, label: string) {
  const { violations } = await new AxeBuilder({ page }).analyze();
  expect(
    violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`),
    label,
  ).toEqual([]);
}

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ request }) => {
  await admin(request, { action: 'reset' });
});
test.afterAll(async ({ request }) => {
  await admin(request, { action: 'reset' });
});

test('refused outside Côte d’Ivoire: the reason, the note, no way to ask again — axe-clean', async ({
  page,
  request,
}) => {
  await admin(request, { action: 'refuse', code: 'outside_ci', note: 'Le pin est à Dakar.' });
  await signInPro(page, OWNER);
  await cardReady(page);
  await expect(page.getByText('Mise en ligne refusée')).toBeVisible();
  await expect(
    page.getByText(
      'MyWeli n’est pas encore disponible dans votre pays. Si votre salon est en Côte d’Ivoire, écrivez-nous depuis « Aide & Support ».',
    ),
  ).toBeVisible();
  await expect(page.getByText('Le pin est à Dakar.')).toBeVisible();
  await expect(page.getByRole('button', { name: /Renvoyer|Demander|Mettre en ligne/ })).toHaveCount(0);
  await expectAxeClean(page, 'the final refusal');

  // The preview says it too — and promises no clients.
  await page.getByRole('link', { name: 'Aperçu de ma page' }).click();
  const banner = page.getByRole('complementary', { name: 'Aperçu du salon' });
  await expect(banner).toContainText('Aperçu — la mise en ligne de votre salon a été refusée.');
  await expect(banner).not.toContainText('Voici ce que verront vos clients');
});

test('refused for its photos → « Renvoyer pour validation » → 202 → pending — axe-clean both ways', async ({
  page,
  request,
}) => {
  await admin(request, { action: 'refuse', code: 'photos', note: 'Plus de lumière, svp.' });
  await signInPro(page, OWNER);
  await cardReady(page);
  await expect(
    page.getByText('Les photos ne montrent pas assez clairement le salon et son travail.'),
  ).toBeVisible();
  await expect(page.getByText('Modifiez votre salon, puis renvoyez-le pour validation.')).toBeVisible();
  await expectAxeClean(page, 'the refused card');

  await page.getByRole('button', { name: 'Renvoyer pour validation' }).click();
  await expect(
    page.getByText('Demande envoyée. Nous vous préviendrons de la décision.'),
  ).toBeVisible();
  await expect(page.getByText('En cours de validation')).toBeVisible();
  await expect(
    page.getByText('Nous examinons votre salon avant sa mise en ligne. Nous vous préviendrons dès que c’est fait.'),
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Renvoyer pour validation' })).toHaveCount(0);
  await expectAxeClean(page, 'the pending card');

  // A reload reads the server's state, not the page's memory.
  await page.reload();
  await expect(page.getByText(/^Demande envoyée le \d{1,2} \S+ \d{4}$/)).toBeVisible();
});

test('MyWeli validates → live: the card goes, the public page is one click away', async ({
  page,
  request,
}) => {
  await admin(request, { action: 'approve' });
  await signInPro(page, OWNER);
  await expect(page.getByRole('heading', { level: 1, name: 'Aujourd’hui' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Voir ma page publique' })).toBeVisible();
  await expect(page.getByText(/En cours de validation|Mise en ligne refusée/)).toHaveCount(0);
});

test('no longer online, offer live → « Remettre en ligne » → 200 → « 🎉 »', async ({ page, request }) => {
  await admin(request, {
    action: 'seed',
    status: 'draft',
    offer: 'live',
    validation: { state: 'approved', decidedAt: '2026-11-01T10:00:00Z', wentLive: true },
  });
  await signInPro(page, OWNER);
  await cardReady(page);
  await expect(page.getByText('Votre salon n’est plus en ligne')).toBeVisible();
  await expect(page.getByText('Vous pouvez le remettre en ligne.')).toBeVisible();
  await page.getByRole('button', { name: 'Remettre en ligne' }).click();
  await expect(
    page.getByText('🎉 Votre salon est en ligne ! Il apparaît maintenant dans les recherches.'),
  ).toBeVisible();
});

test('a server before B0.18 (no `validation`): today’s « Mettre en ligne », live at once', async ({
  page,
  request,
}) => {
  await admin(request, { action: 'reset' });
  await admin(request, { action: 'seed', legacy: true });
  await signInPro(page, OWNER);
  await cardReady(page);
  await expect(page.getByText('Votre salon n’est pas encore en ligne')).toBeVisible();
  await page.getByRole('button', { name: 'Mettre en ligne' }).click();
  await expect(
    page.getByText('🎉 Votre salon est en ligne ! Il apparaît maintenant dans les recherches.'),
  ).toBeVisible();
  await expect(page.getByText(/Demande envoyée/)).toHaveCount(0);
});

test('`/pro?salon=` (a decision’s notice): two salons — switched once, the address dropped', async ({
  page,
}) => {
  // The default owner holds p1 and p3; only this browser's selection moves.
  await signInPro(page);
  await page.goto('/pro?salon=p3');
  await expect(page).toHaveURL(/\/pro$/);
  await expect(page.getByRole('button', { name: 'Changer de salon' })).toContainText(
    'Institut Belle Vue',
  );
  await expect(page.getByText('Votre salon n’est pas encore en ligne')).toBeVisible();
  // A later switch from « Mes salons » is not pulled back to p3.
  await page.getByRole('button', { name: 'Changer de salon' }).click();
  await page.getByRole('button', { name: /Beauté Divine/ }).click();
  await expect(page.getByRole('button', { name: 'Changer de salon' })).toContainText('Beauté Divine');
  await page.waitForTimeout(300);
  await expect(page.getByRole('button', { name: 'Changer de salon' })).toContainText('Beauté Divine');
});
