import { expect, type Page } from '@playwright/test';

/// The one e2e sign-in (B9).
///
/// **There were six copies**, and the duplication was not cosmetic — it is why
/// `type-overflow.spec.ts` never grew a real authed matrix. That file's route
/// table is `PUBLIC_ROUTES`, and every authed page it wanted had to be a
/// hand-written `test()` with its own copy of the login below. Two got written;
/// one of them then forgot to run the assertions the file exists for
/// (`/pro/rendez-vous` asserted a computed `line-height` and nothing else, on
/// the page carrying the first tab strip). A matrix you have to hand-extend one
/// `async function` at a time is a matrix that stops being extended.
///
/// The six: `pro.spec.ts`, `tap-targets.spec.ts`, `axe.spec.ts`,
/// `pro-mobile-nav.spec.ts`, `type-overflow.spec.ts`, and inline in
/// `booking.spec.ts` / `account.spec.ts`.
///
/// **Selectors are the accessible ones.** Four of the six drove
/// `input[type=email]` / `input[type=text]`; two used `getByLabel`. The label
/// form is the one WEB-SYSTEM §6 mandates the markup to support ("a placeholder
/// is not a label"), so a login that breaks when a label is dropped is a login
/// that fails for the right reason. Both surfaces render the same two labels —
/// `components/auth/LoginOptions.tsx:334,273` and
/// `components/pro/ProLoginOptions.tsx:284,229`.
///
/// Credentials are the stub API's (`tests/e2e/stub-api.mjs`), not secrets.

export const PRO_EMAIL = 'salon@example.com';
export const CONSUMER_EMAIL = 'client@example.com';

/// Fills and submits the OTP form **on the page you are already on**.
///
/// Split out because two callers arrive at `/connexion` by redirect rather than
/// by navigation (`axe.spec.ts` scans the page first; `booking.spec.ts` is
/// bounced there mid-flow), and making them navigate would change what they
/// test.
export async function submitOtpLogin(page: Page, email: string): Promise<void> {
  await page.getByLabel('Votre e-mail').fill(email);
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.getByLabel('Code à 6 chiffres').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
}

/// Navigate to the pro login and sign in, **asserting arrival**.
///
/// The assertion is not decoration: without it a failed login leaves the test on
/// `/pro/connexion`, and a gate that then measures the login page reports green
/// about a page it was not asked about — the vacuity this repo has recorded
/// twice (SYSTEM §20; `type-overflow.spec.ts`'s own anchor comment).
export async function signInPro(page: Page, email = PRO_EMAIL): Promise<void> {
  await page.goto('/pro/connexion');
  await submitOtpLogin(page, email);
  await expect(page, 'the pro login did not land on /pro').toHaveURL(
    /\/pro(\/)?$/,
  );
}

/// Navigate to the consumer login and sign in, asserting arrival.
export async function signInConsumer(
  page: Page,
  email = CONSUMER_EMAIL,
): Promise<void> {
  await page.goto('/connexion');
  await submitOtpLogin(page, email);
  await expect(page, 'the consumer login did not land on /mon-compte').toHaveURL(
    /\/mon-compte/,
  );
}
