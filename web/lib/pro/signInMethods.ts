/// The ways into the Espace Pro that THIS build offers, read in one place.
///
/// `/pro/connexion` draws « Continuer avec Google » only with
/// NEXT_PUBLIC_GOOGLE_CLIENT_ID and « Continuer avec Apple » only with
/// NEXT_PUBLIC_APPLE_CLIENT_ID; « Continuer avec e-mail » always. The static
/// `/pro/suppression-compte` tells a salon which button to press, so it must
/// name a method exactly when the same build draws it: both read this helper
/// (docs/design/web-pro-account-deletion.md §5.1, §7; held by
/// `tests/pro-sign-in-methods.test.ts`).
///
/// **Literal `process.env.NEXT_PUBLIC_…` reads, on purpose.** Next inlines a
/// public variable only where it is written out like this; `process.env[name]`
/// would be `undefined` in the browser and the buttons would vanish. A function,
/// not a constant, so a test can set the variables before it reads them.
/// An empty variable is no id at all, as the sign-in's truthiness test had it.
export type SignInMethods = {
  /// The Google client id, when the build has one.
  readonly google: string | undefined;
  /// The Apple Services ID, when the build has one.
  readonly apple: string | undefined;
};

export function signInMethods(): SignInMethods {
  return {
    google: process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID || undefined,
    apple: process.env.NEXT_PUBLIC_APPLE_CLIENT_ID || undefined,
  };
}
