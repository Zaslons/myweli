import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

import { submitOtpLogin } from './_auth';

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

/// A 1×1 transparent GIF — the smallest thing that actually DECODES.
///
/// Fulfilled rather than aborted: a fulfilled image stays "loaded", so layout,
/// paint and `naturalWidth` are unchanged and no `net::ERR_FAILED` reaches the
/// console. Aborting would change what axe sees on the pages that carry photos.
const PIXEL = Buffer.from(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
  'base64',
);

test.beforeEach(async ({ page }) => {
  // Hermetic like every other map spec: live basemap traffic both stalls
  // networkidle on CI and makes the scanned DOM depend on CDN reachability.
  await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());

  /// **The server-side half, and it is the one that is easy to miss.**
  /// `next.config.mjs` allow-lists `cdn.stub` in `remotePatterns`, so every
  /// `next/image` with a stub photo emits a SAME-ORIGIN
  /// `/_next/image?url=https%3A%2F%2Fcdn.stub%2F…` and the **Next process**
  /// then calls `fetch('https://cdn.stub/…')` — with no `AbortSignal` and no
  /// timeout (`next/dist/server/image-optimizer.js:722`). The browser never
  /// requests `cdn.stub`, so a `page.route` on that host cannot intercept it,
  /// and the DNS failure burns wall-clock inside the server on libuv's
  /// 4-thread pool. Intercepting here means the request never reaches Next.
  await page.route('**/_next/image**', (r) =>
    r.fulfill({ status: 200, contentType: 'image/gif', body: PIXEL }),
  );

  /// The browser-side half — the raw `<img>` tags `next/image` never touches
  /// (`components/provider/ReviewList.tsx:62`, seeded in `stub-api.mjs`). These
  /// DO go direct, so this route is both necessary and sufficient for them.
  await page.route('**/cdn.stub/**', (r) =>
    r.fulfill({ status: 200, contentType: 'image/gif', body: PIXEL }),
  );
});

/// Waits for the route to have rendered **its own page**, then scans.
///
/// **`networkidle` used to stand here, and it was wrong twice.**
///
/// 1. *It flakes.* `page.waitForLoadState('networkidle')` cannot settle while
///    the server is resolving an unreachable host, which is what
///    `/_next/image` did above. It took a 30s test budget with it, and the
///    stack blamed whichever route happened to be in flight.
///    `type-overflow.spec.ts:369-372` had already written this down — *"`next/
///    image` keeps the network busy past the 30s timeout"* — and solved it with
///    a per-route anchor. This file kept `networkidle` in three places anyway.
/// 2. *It hid a vacuity hole.* Waiting on the network says nothing about
///    **which** DOM arrived. Every one of these 19 routes was scanned with no
///    anchor at all, so a 404 — or an `ErrorState` — would have been scanned
///    instead, found no violations, and passed. B8 caught exactly that in the
///    overflow gate: a slug rename had left a route measuring the 404 page for
///    months, and the 404 page does not overflow either.
///
/// So the anchor is the fix for both: it is the render signal *and* the vacuity
/// guard, which is the shape `type-overflow.spec.ts` settled on.
///
/// [ready] is a **second stage** and is not decoration. Three of these routes
/// paint their `<h1>` from the first fetch and their content from a second one,
/// and `networkidle` was implicitly waiting for both. An anchor-only wait would
/// therefore *regress* coverage and race a DOM mutation under axe.
async function scan(
  page: import('@playwright/test').Page,
  where: string,
  anchor: string | RegExp,
  ready?: (p: import('@playwright/test').Page) => import('@playwright/test').Locator,
) {
  await expect(
    // `.first()`: /recherche carries a responsive heading twin (a visible h1
    // plus an `sr-only lg:hidden` one). One is enough to prove the DOM is right.
    page.getByRole('heading', { name: anchor }).first(),
    `${where} did not render its own page (wrong DOM — vacuous scan)`,
  ).toBeVisible();
  if (ready) await expect(ready(page)).toBeVisible();

  /// **`ErrorState` renders the page's own `<h1>`** (`ErrorState.tsx:32`), so
  /// the anchor above passes on a failed load. Its `role="alert"` is the only
  /// thing that distinguishes them.
  ///
  /// The `.filter(Boolean)` is load-bearing: Next ships an empty
  /// `<div id="__next-route-announcer__" role="alert">` on every page, and
  /// keying on the role alone reddens every route (B11 measured this).
  expect(
    (await page.getByRole('alert').allTextContents())
      .map((t) => t.trim())
      .filter(Boolean),
    `${where} rendered an error state — the axe scan below would be vacuous`,
  ).toEqual([]);

  await expectNoViolations(page, where);
}

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


/// Every anchor here is lifted from a spec that already proves it green —
/// `type-overflow.spec.ts`'s route tables and `landing.spec.ts:12` — rather
/// than invented for this file. The legal four come from `lib/legal.ts`'s `h1`
/// field, which is the single source those pages render from.
const PUBLIC_ROUTES: [url: string, anchor: string | RegExp][] = [
  ['/', /Réservez beauté/],
  ['/recherche?commune=Cocody', /Salons à Cocody/],
  // A **regex**, not the exact string: `pro.spec.ts` renames the shared stub
  // salon to « Beauté Divine Web » from another worker, and Playwright's
  // string `name:` is an exact match. `roles.spec.ts` already tolerates this
  // the same way.
  ['/beaute-divine', /Beauté Divine/],
  ['/beaute-divine/reserver', /Réserver chez/],
  ['/connexion', /Connexion|Se connecter|e-mail/i],
  ['/pro/connexion', 'Espace Pro'],
  // The review's finds: an AREA taxonomy landing (its h1→h3 skip survived
  // the first matrix) — landing.spec's own stub route.
  ['/coiffure/abidjan/cocody', 'Coiffure à Cocody'],
  // L1 — the four legal documents. They also carry the site's FIRST <footer>,
  // so these runs are the first time axe sees that landmark at all.
  ['/politique-confidentialite', 'Politique de confidentialité'],
  ['/cgu', 'Conditions générales d’utilisation'],
  ['/mentions-legales', 'Mentions légales'],
  ['/suppression-compte', 'Supprimer votre compte'],
];

test('public routes are axe-clean', async ({ page }) => {
  for (const [url, anchor] of PUBLIC_ROUTES) {
    await page.goto(url);
    await scan(page, url, anchor);
  }
});

test('consumer account routes are axe-clean', async ({ page }) => {
  await page.goto('/connexion');
  await submitOtpLogin(page, 'client@example.com');
  await page.waitForURL(/mon-compte|\/$/);
  for (const [url, anchor, ready] of [
    // `/mon-compte`'s heading lands before the bookings do — the filter group
    // is `type-overflow.spec.ts`'s own second stage for this exact route.
    ['/mon-compte', 'Mon compte',
      (p: import('@playwright/test').Page) =>
        p.getByRole('group', { name: 'Filtrer mes rendez-vous' })],
    ['/mon-compte/notifications', 'Notifications'],
    // The booking detail page titles itself with the SALON, not the booking —
    // « Beauté Divine », level 1. Guessed wrong first; the failure's own
    // accessibility-tree dump is what corrected it.
    ['/mon-compte/appt2', /Beauté Divine/],
  ] as [string, string | RegExp, ((p: import('@playwright/test').Page) => import('@playwright/test').Locator)?][]) {
    await page.goto(url);
    await scan(page, url, anchor, ready);
  }
});

test('pro routes are axe-clean', async ({ page }) => {
  await page.goto('/pro/connexion');
  await submitOtpLogin(page, 'salon@example.com');
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  for (const [url, anchor] of [
    ['/pro', /Aujourd’hui/],
    ['/pro/rendez-vous', 'Rendez-vous'],
    ['/pro/equipe', 'Équipe'],
    ['/pro/clients', 'Clients'],
    // **Not the h1.** `/pro/apercu` renders three different `<main>`s — loading,
    // error and loaded (`SalonPreviewClient.tsx:46,:54,:69`) — and `pro.spec.ts`
    // renames the shared stub salon from another worker, so its heading is not
    // name-stable. The preview banner is an `<aside aria-label>` that exists
    // **only** in the loaded state, which is exactly the signal wanted.
    ['/pro/apercu', null],
  ] as [string, (string | RegExp) | null][]) {
    await page.goto(url);
    if (anchor === null) {
      await expect(
        page.getByRole('complementary', { name: 'Aperçu du salon' }),
        `${url} did not render its own page (wrong DOM — vacuous scan)`,
      ).toBeVisible();
      await expectNoViolations(page, url);
    } else {
      await scan(page, url, anchor);
    }
  }
});

test('an OPEN dialog is axe-clean (the stateful scan a crawl never sees)', async ({
  page,
}) => {
  await page.goto('/pro/connexion');
  await submitOtpLogin(page, 'salon@example.com');
  await expect(page).toHaveURL(/\/pro(\/)?$/);
  await page.goto('/pro/clients');
  await page.getByRole('button', { name: 'Ajouter un client' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expectNoViolations(page, '/pro/clients + add-client Modal');
});

test('a VISIBLE toast is axe-clean', async ({ page }) => {
  await page.goto('/pro/connexion');
  await submitOtpLogin(page, 'salon@example.com');
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
