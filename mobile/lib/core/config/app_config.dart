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
