import { expect, test } from '@playwright/test';

/// L1 — the four legal documents, and the site's first `<footer>`.
///
/// **Why this file exists.** Both app stores take a privacy-policy URL as a
/// submission field, and Google Play has taken an account-deletion URL since
/// 2023. Before L1 there was no legal document in any surface of this product —
/// and three app screens already told users « vous acceptez nos conditions
/// d'utilisation » in dead, unlinked text, pointing at documents that did not
/// exist.
///
/// **What a store reviewer does is exactly this test**: open the URL, signed
/// out, on a phone, and read it. So every assertion here is something that
/// breaks the submission if it fails — a 404, a page with no heading, a
/// canonical that points somewhere else.
///
/// `axe.spec.ts` covers the accessibility of these same routes, and
/// `type-overflow.spec.ts` covers `/suppression-compte` at 375px. This file
/// covers what those two cannot see: that the document is *there*, that it says
/// when it was last updated, and that its structured data parses.

const LEGAL: [slug: string, h1: RegExp][] = [
  ['/politique-confidentialite', /Politique de confidentialité/i],
  ['/cgu', /Conditions générales d’utilisation/i],
  ['/mentions-legales', /Mentions légales/i],
  ['/suppression-compte', /Supprimer votre compte/i],
];

for (const [slug, h1] of LEGAL) {
  test(`${slug} — reachable, headed, canonical, structured`, async ({
    page,
  }) => {
    const res = await page.goto(slug);
    expect(res?.status(), `${slug} must not 404`).toBe(200);

    // Exactly one h1 — WEB-SYSTEM §4: "One <h1> per page = the page's core
    // entity." A legal document with two is a document that got pasted twice.
    const headings = page.getByRole('heading', { level: 1 });
    await expect(headings).toHaveCount(1);
    await expect(headings.first()).toHaveText(h1);

    // The date, from the single `LEGAL_UPDATED_AT` — four pages cannot drift
    // apart if they read one constant.
    await expect(page.getByText(/Dernière mise à jour/i)).toBeVisible();

    // Canonical: these pages are indexable, and a wrong canonical on a legal
    // document is the kind of thing nobody notices for a year.
    const canonical = page.locator('link[rel="canonical"]');
    await expect(canonical).toHaveAttribute('href', new RegExp(`${slug}$`));

    // The counsel marker from the SPEC must never reach shipped copy.
    await expect(page.locator('body')).not.toContainText(/à valider/i);

    // Every JSON-LD block on the page must parse and name a type.
    const blocks = await page
      .locator('script[type="application/ld+json"]')
      .allTextContents();
    expect(blocks.length, `${slug} emits JSON-LD`).toBeGreaterThan(0);
    const types = blocks.map((b) => JSON.parse(b)['@type']);
    expect(types, `${slug} JSON-LD @types`).toContain('WebPage');
    expect(types).toContain('BreadcrumbList');
  });
}

test('the footer is on every page, and it links all four', async ({ page }) => {
  // Not a legal-page assertion — a SITE assertion. WEB-SYSTEM §4 has mandated
  // a `<footer>` landmark since it was written, and the product had none
  // anywhere; the register recorded neither the rule nor the violation.
  for (const route of ['/', '/connexion', '/suppression-compte']) {
    await page.goto(route);
    const footer = page.getByRole('contentinfo');
    await expect(footer, `${route} has a footer`).toBeVisible();
    for (const name of [
      'Politique de confidentialité',
      'Conditions d’utilisation',
      'Mentions légales',
      'Supprimer mon compte',
    ]) {
      await expect(
        footer.getByRole('link', { name }),
        `${route} footer → ${name}`,
      ).toBeVisible();
    }
  }
});

test('the deletion page tells you what survives, not just what goes', async ({
  page,
}) => {
  // The page exists to answer a store reviewer's question, and the honest
  // answer has three parts. A page that only lists what is deleted is the
  // failure mode this asserts against — it would be describing an erasure the
  // backend does not perform (see docs/design/account-deletion-erasure.md).
  await page.goto('/suppression-compte');
  const body = page.locator('body');
  await expect(body).toContainText(/supprimé/i);
  await expect(body).toContainText(/anonymisé/i);
  await expect(body).toContainText(/conservé/i);
  // And the two things a user must be able to act on.
  await expect(body).toContainText(/Profil/);
  await expect(body).toContainText(/exporter/i);
});
