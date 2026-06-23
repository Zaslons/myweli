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
}
