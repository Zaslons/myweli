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

  /// The home's « stories » row — **OFF**.
  ///
  /// Its three stories are hard-coded demo content
  /// (`widgets/home/announcement_stories.dart` and
  /// `assets/images/stories/`): a « -15 % » weekend offer nobody makes, and a
  /// « Nouveau salon », « Beauté Divine », that does not exist. Shown to a
  /// client, they are a false offer (App Store 2.3.1, Play's
  /// deceptive-behaviour policy). The owner chose to keep the feature rather
  /// than remove it (decision 170, 2026-11-23): it stays in the tree, hidden,
  /// until someone manages real stories. Then the hard-coded list gives way to
  /// that source and this flips on.
  ///
  /// `feature_flags_test.dart` turns red if this is on while the demo
  /// stories are still in the tree. Design:
  /// docs/design/consumer-app-truth.md §2.1.
  static const bool homeStories = false;

  /// The manual-booking « Envoyer la confirmation par SMS » switch — **OFF**.
  /// The server never reads `sendSmsInvite` and messaging is switched off until
  /// the company is registered (SMS/WhatsApp are post-launch), so the switch
  /// promised something that could not happen. While false the form hides it
  /// and sends `false`; flip it when a MessagingProvider sends the invite
  /// (docs/design/pro-screenshot-shoot-fixes.md §1.6).
  static const bool smsInvite = false;

  /// Sign in with Apple — **ON**. It shipped dark while there was no Apple
  /// Developer account; there is one now, the Services ID and APNs key are
  /// configured, and the flow is verified end to end on iOS, Android and web.
  ///
  /// **Defaulted rather than left to a `--dart-define`, deliberately.** App
  /// Store rule 4.8 REQUIRES Sign in with Apple on iOS whenever another
  /// third-party sign-in is offered, and we offer Google. While this read
  /// `bool.fromEnvironment('APPLE_SIGN_IN')` — passed by no build, no CI job
  /// and no line of DEPLOYMENT.md — every release build showed Google and
  /// e-mail and **no Apple button**, which is a rejectable submission. A
  /// store-review requirement must not depend on remembering a build flag.
  ///
  /// Override to hide it again with `--dart-define=APPLE_SIGN_IN=false`.
  /// Design: docs/design/app-auth-social.md §5.
  static const bool appleSignIn = bool.fromEnvironment(
    'APPLE_SIGN_IN',
    defaultValue: true,
  );
}
