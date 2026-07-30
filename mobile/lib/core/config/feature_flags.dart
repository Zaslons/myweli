/// Central switches for features that are not part of the current V1 release.
///
/// The eight provider "feature" modules under `screens/provider/features/`
/// (loyalty programs, inventory, payroll, reports/analytics, client database,
/// booking journal, online booking, WhatsApp notifications) are **V2/V3**.
/// They stay in the tree but are gated off so they cannot ship in V1 — each
/// screen short-circuits to a "coming soon" placeholder while this is false.
/// Flip to enable when those phases land.
class FeatureFlags {
  const FeatureFlags._();

  static const bool futureProviderFeatures = false;

  /// Sign in with Apple — the seam ships dark until the Apple Developer
  /// account exists (store phase; App Store rule 4.8 then REQUIRES it on iOS).
  /// Enable with `--dart-define=APPLE_SIGN_IN=true`.
  /// Design: docs/design/app-auth-social.md §5.
  static const bool appleSignIn = bool.fromEnvironment('APPLE_SIGN_IN');
}
