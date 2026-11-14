import { expect, test, type Page } from '@playwright/test';
import { PRO_EMAIL, submitOtpLogin } from './_auth';

/// `/pro/suppression-compte` on the built app (B0.19,
/// docs/design/web-pro-account-deletion.md §10 #13 and #16): what Google Play's
/// reviewer, and a salon without the app, open from the Data safety link.
///
/// **The header is read inside its landmark.** The footer prints « Connexion
/// Espace pro » here (its salons' group shows on every page but the five), so
/// a document-wide « Espace pro » check would pass on a page whose chrome had
/// rendered no header at all — which is exactly what `SiteChrome` does for a
/// `/pro/…` path missing from `PRO_AUTH`.

const PATH = '/pro/suppression-compte';
const H1 = 'Supprimer votre compte MyWeli Pro';
const LISTING = 'MyWeli Pro — Gestion de salon';
const CTA = 'Se connecter à l’Espace Pro';
const LEGAL = ['Politique de confidentialité', 'Conditions d’utilisation', 'Mentions légales', 'Supprimer mon compte'];

const jsonLdTypes = (page: Page) =>
  page
    .locator('script[type="application/ld+json"]')
    .evaluateAll((all) => all.map((s) => (JSON.parse(s.textContent ?? '{}') as { '@type'?: string })['@type']));

test.describe('signed out, on a phone', () => {
  test.use({ viewport: { width: 375, height: 812 } });

  test('200; one h1; the listing name before the first h2; the CTA; canonical; JSON-LD; the chrome', async ({ page }) => {
    const res = await page.goto(PATH);
    expect(res?.status()).toBe(200);
    await expect(page.getByRole('heading', { level: 1 })).toHaveCount(1);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(H1);

    const order = await page.evaluate((listing) => {
      const els = [...document.querySelectorAll('main p, main h2')];
      return {
        lead: els.findIndex((e) => e.tagName === 'P' && (e.textContent ?? '').includes(listing)),
        h2: els.findIndex((e) => e.tagName === 'H2'),
      };
    }, LISTING);
    expect(order.lead, 'no paragraph names the Play listing').toBeGreaterThanOrEqual(0);
    expect(order.lead, 'the listing name comes after the first h2').toBeLessThan(order.h2);

    const cta = page.getByRole('link', { name: CTA });
    await expect(cta).toBeVisible();
    await expect(cta).toHaveAttribute('href', '/pro/connexion?suite=profil');
    const box = await cta.boundingBox();
    expect(box!.height, 'the CTA is under the 48px floor').toBeGreaterThanOrEqual(48);

    expect(await page.locator('link[rel="canonical"]').getAttribute('href')).toMatch(/\/pro\/suppression-compte$/);
    expect(await jsonLdTypes(page)).toEqual(expect.arrayContaining(['WebPage', 'BreadcrumbList', 'FAQPage']));

    const banner = page.getByRole('banner');
    await expect(banner).toContainText('Espace pro');
    await expect(banner.getByRole('link', { name: 'MyWeli — accueil' })).toHaveAttribute('href', '/');
    await expect(banner.getByRole('link', { name: 'Mon compte' })).toHaveCount(0);

    // Outside the five, so the salons' group shows; the legal links stay.
    const footer = page.getByRole('contentinfo');
    await expect(footer.getByRole('navigation', { name: 'Professionnels' })).toBeVisible();
    for (const label of LEGAL) await expect(footer.getByRole('link', { name: label })).toBeVisible();
  });

  test('the CTA opens the sign-in with ?suite=profil, and the sign-in lands on Profil', async ({ page }) => {
    await page.goto(PATH);
    await page.getByRole('link', { name: CTA }).click();
    await expect(page).toHaveURL(/\/pro\/connexion\?suite=profil$/);
    await expect(page.getByRole('heading', { level: 1, name: 'Espace Pro' })).toBeVisible();
    await submitOtpLogin(page, PRO_EMAIL);
    await expect(page, 'the sign-in did not come back to Profil').toHaveURL(/\/pro\/profil$/);
    // The section step 3 names, and its button.
    await expect(page.getByRole('heading', { level: 2, name: 'Compte' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Supprimer mon compte' })).toBeVisible();
  });
});

test.describe('JavaScript off — what a crawler and a slow phone get', () => {
  test.use({ javaScriptEnabled: false, viewport: { width: 375, height: 812 } });

  test('the h1, the CTA and the Pro header are in the served page', async ({ page }) => {
    await page.goto(PATH);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(H1);
    await expect(page.getByRole('link', { name: CTA })).toHaveAttribute('href', '/pro/connexion?suite=profil');
    const banner = page.getByRole('banner');
    await expect(banner).toHaveCount(1);
    await expect(banner).toContainText('Espace pro');
    await expect(banner.getByRole('link', { name: 'MyWeli — accueil' })).toHaveAttribute('href', '/');
  });

  test('raw HTML: the <header> element itself holds the lockup and « Espace pro »', async ({ request }) => {
    const html = await (await request.get(PATH)).text();
    const header = /<header\b[\s\S]*?<\/header>/.exec(html)?.[0];
    expect(header, 'the served page has no <header>').toBeTruthy();
    expect(header).toContain('aria-label="MyWeli — accueil"');
    expect(header).toContain('Espace pro');
    expect(header).not.toContain('Mon compte');
  });
});

/// #16 — indexed (decision 140). `served-html.spec.ts` reads only three-segment
/// URLs, so it would never see this two-segment path: this takes the page's
/// exact `<loc>` from the sitemap and asks it the two questions a crawler does.
test('the sitemap lists it, and that URL answers 200 and lets crawlers index it', async ({ request }) => {
  const xml = await (await request.get('/sitemap.xml')).text();
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  const loc = locs.find((u) => new URL(u).pathname === PATH);
  expect(loc, `${PATH} is not in the sitemap`).toBeTruthy();
  const res = await request.get(new URL(loc!).pathname);
  expect(res.status(), `${loc} is listed but does not answer`).toBe(200);
  const html = await res.text();
  expect(/<meta[^>]+name="robots"[^>]+noindex/i.test(html), `${loc} tells crawlers not to index it`).toBe(false);
  expect(html).toMatch(/<meta name="robots" content="index, follow"/);
});
