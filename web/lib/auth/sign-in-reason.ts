/// Why `/connexion` opened, written under its title — the app's reason line
/// (docs/design/consumer-signin-push.md §2.2 and §14.2). A known key maps to a
/// fixed sentence; nothing from the address is ever written to the page.
export const SIGN_IN_REASONS = {
  favori: 'Connectez-vous pour ajouter ce salon à vos favoris.',
} as const;

export type SignInReason = keyof typeof SIGN_IN_REASONS;

export function signInReasonLine(raw: string | string[] | undefined): string | null {
  if (typeof raw !== 'string') return null;
  // Own keys only: `toString` or `__proto__` are not reasons.
  return Object.prototype.hasOwnProperty.call(SIGN_IN_REASONS, raw)
    ? SIGN_IN_REASONS[raw as SignInReason]
    : null;
}
