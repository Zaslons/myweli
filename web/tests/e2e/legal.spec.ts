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

/// What the page PROMISES, checked against what the built app DOES.
///
/// **Why this is here and not in `legal.test.tsx`.** That file renders the TSX
/// and greps `package.json`. Both of this project's privacy failures lived in
/// the served bundle, where it cannot look:
///
///   2026-08-12  the live policy denied using Sentry while the bundle posted to it
///   2026-08-20  the live policy said « aucun rapport … lorsque rien n'a échoué »
///               while a clean page load sent THREE session envelopes carrying
///               the session id, the release and the full user-agent
///
/// The second one is the sharper lesson. `legal.test.tsx`'s own comment records
/// that a broader version of it "failed on a sentence that is true" — so the
/// guard was narrowed to exempt that sentence, and the sentence was false. It
/// resolved an ambiguity by assuming rather than measuring.
///
/// **The Sentry half of this is NOT here, deliberately.** `Sentry.init` does not
/// run client-side in the e2e build — no client is created, so every in-browser
/// assertion about it passes for the wrong reason. Three attempts to make one
/// fail are recorded in `tool/check-privacy-promise.spec.ts`, which runs the
/// same checks against a DEPLOYED url, where the SDK is live. What remains here
/// is the cookie half, which does discriminate.
test.describe('the privacy policy is true of the built app', () => {
  test('a public page sets no cookie at all', async ({ page, context }) => {
    await context.clearCookies();
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    const jar = await context.cookies();
    expect(
      jar.map((c) => c.name),
      '« Sur les pages publiques, aucun cookie n’est déposé »',
    ).toEqual([]);
  });

  /// **« tant que vous ne choisissez pas Google, rien n'est envoyé à Google ».**
  ///
  /// Until 2026-08-21 that was false: the script was fetched from a mount-time
  /// effect, so simply opening this page disclosed the visitor's IP and
  /// user-agent to Google and let it set `g_state`. Measured on production,
  /// zero interaction, with `/` as the control:
  ///
  ///   /           third-party hosts: (none)                    cookies: (none)
  ///   /connexion  third-party hosts: accounts.google.com, …    cookies: g_state
  ///
  /// **Requests are intercepted, never allowed out.** Letting the suite really
  /// fetch from Google would make CI depend on a third party's uptime and would
  /// have this repo contact Google on every run to prove it does not contact
  /// Google. Aborting the route still proves the request was ATTEMPTED, which
  /// is the thing being asserted.
  ///
  /// **The tap is the control.** Without it, "zero requests to Google" is also
  /// what a page with no Google button at all would report — and that is not a
  /// hypothetical: this file's previous version asserted cookies on a page
  /// where `NEXT_PUBLIC_GOOGLE_CLIENT_ID` was unset, so the button never
  /// rendered and the loop it ran had nothing to iterate.
  test('the sign-in page contacts Google only after the visitor chooses Google', async ({
    page,
    context,
  }) => {
    await context.clearCookies();
    const googleHits: string[] = [];
    await page.route('**://accounts.google.com/**', (route) => {
      googleHits.push(route.request().url());
      return route.abort();
    });

    await page.goto('/connexion');
    await page.waitForLoadState('networkidle');

    expect(
      googleHits,
      'opening the sign-in page must not reach Google — nothing has been chosen yet',
    ).toEqual([]);
    expect(
      (await context.cookies()).map((c) => c.name),
      'no cookie may be set before the visitor chooses a sign-in method',
    ).toEqual([]);

    // The control: our own facade is present, and pressing it DOES reach out.
    const facade = page.getByRole('button', { name: /Continuer avec Google/i });
    await expect(facade).toBeVisible();
    await facade.click();
    await expect
      .poll(() => googleHits.length, {
        message:
          'the facade must actually load GSI — otherwise the assertion above '
          + 'is satisfied by a button that does nothing',
      })
      .toBeGreaterThan(0);
  });

  /// The broader claim, and the one that would have caught the Google script
  /// on its own: the sign-in page reaches NO third party before a choice is
  /// made. Nothing in `web/` inspected requests before this.
  test('the sign-in page loads no third-party resource at all', async ({
    page,
    context,
  }) => {
    await context.clearCookies();
    const foreign = new Set<string>();
    page.on('request', (r) => {
      const host = new URL(r.url()).hostname;
      if (host !== '127.0.0.1' && host !== 'localhost') foreign.add(host);
    });
    await page.goto('/connexion');
    await page.waitForLoadState('networkidle');
    expect(
      [...foreign],
      'every host here is one the privacy policy must name',
    ).toEqual([]);
  });
});
