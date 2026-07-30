/// Build-time configuration, supplied via `--dart-define`.
///
/// Defaults keep the app fully on mocks, so every test and the default run are
/// unchanged. Point it at the backend during development with, e.g.:
///
/// ```sh
/// flutter run \
///   --dart-define=USE_API_BACKEND=true \
///   --dart-define=API_BASE_URL=http://10.0.2.2:8080   # Android emulator → host
/// ```
class AppConfig {
  const AppConfig._();

  /// Base URL of the Myweli API (no trailing slash).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// When true, dependency injection wires the real `Api*` services for the
  /// interfaces that have a backend slice; everything else stays on mocks.
  /// Off by default so the app runs end-to-end without a server.
  static const bool useApiBackend = bool.fromEnvironment('USE_API_BACKEND');

  /// Myweli support WhatsApp number in E.164 without `+` (e.g. `2250700000000`).
  /// Used by "Nous contacter" CTAs (e.g. the provider subscription screen).
  /// Empty by default → the CTA degrades gracefully until set at launch via
  /// `--dart-define=SUPPORT_WHATSAPP=225...`.
  static const String supportWhatsApp = String.fromEnvironment(
    'SUPPORT_WHATSAPP',
  );

  /// The public site (no trailing slash) — where the legal documents live.
  ///
  /// **The default is inverted from [supportWhatsApp]'s, deliberately.** That
  /// one defaults to empty and its CTA degrades gracefully, because a missing
  /// support number is a missing convenience. A missing privacy-policy link is a
  /// **rejected store submission**, so here the production URL is the default
  /// and the env var is the *staging* override.
  ///
  /// `myweli.com`, not `.ci`: `render.yaml` and `docs/DEPLOYMENT.md` both use
  /// `.com`, and `PRD.md:506`'s `.ci` is stale. Switching later is one define.
  static const String siteBaseUrl = String.fromEnvironment(
    'SITE_BASE_URL',
    defaultValue: 'https://myweli.com',
  );

  /// The four legal documents (L1 — docs/design/legal-l1.md).
  ///
  /// **One base and four getters, not four env vars**, because these paths are a
  /// contract with `web/lib/legal.ts` and must move together — four independent
  /// variables invite three of them being right. **No mobile test can reach the
  /// web**, so that contract is held by review, in one PR, and by
  /// `web/tests/legal.test.tsx` pinning the web half.
  static String get privacyUrl => '$siteBaseUrl/politique-confidentialite';
  static String get termsUrl => '$siteBaseUrl/cgu';
  static String get legalNoticeUrl => '$siteBaseUrl/mentions-legales';
  static String get accountDeletionUrl => '$siteBaseUrl/suppression-compte';

  /// Google Sign-In server client ID (the **web** OAuth client) — makes the
  /// native flow return an ID token whose `aud` the backend allowlists.
  /// A public identifier, not a secret; overridable per environment.
  /// Design: docs/design/app-auth-social.md §5.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '731308991240-dairlha8r67p4l5d52m44qnt82qdp5js.apps.googleusercontent.com',
  );
}
