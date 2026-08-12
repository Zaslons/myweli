import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Severity of a log entry.
enum LogLevel { debug, info, warning, error }

/// Lightweight logging + error-reporting seam for Myweli.
///
/// All app logs and uncaught errors flow through here so a crash reporter
/// (Sentry / Crashlytics) can be plugged in later without touching call sites.
/// It uses `dart:developer`'s `log` rather than `print` (which the lints ban),
/// and suppresses fine-grained logs in release builds to avoid leaking detail
/// and to keep release output cheap.
class AppLogger {
  const AppLogger._();

  static void debug(String message) => _log(LogLevel.debug, message);

  static void info(String message) => _log(LogLevel.info, message);

  static void warning(String message) => _log(LogLevel.warning, message);

  /// Where errors go beyond the console — set once at startup by
  /// `core/observability/error_reporting.dart`, null everywhere else.
  ///
  /// **A hook rather than an import, so this file still knows nothing about
  /// Sentry.** That was the promise in the class doc above ("a crash reporter
  /// can be plugged in later without touching call sites") and it is worth
  /// keeping: `AppLogger` is imported by roughly every layer, and a reporter
  /// dependency here would put a network SDK in the import graph of every unit
  /// test.
  ///
  /// Null in tests, so the suite neither reports nor needs a DSN.
  static void Function(String message, {Object? error, StackTrace? stackTrace})?
  onError;

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, error: error, stackTrace: stackTrace);
    // The single integration point, as the class doc promised. `main.dart`
    // already funnels `FlutterError.onError` and every uncaught async error
    // through `runZonedGuarded` into here, so wiring this one call site covers
    // the framework, the zone, and every explicit `AppLogger.error` in the app.
    //
    // Failures are swallowed: reporting must never become the crash.
    try {
      onError?.call(message, error: error, stackTrace: stackTrace);
    } catch (_) {}
  }

  static void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Debug/info are noise in release: skip them.
    if (kReleaseMode && (level == LogLevel.debug || level == LogLevel.info)) {
      return;
    }
    developer.log(
      message,
      name: 'myweli.${level.name}',
      level: _severity(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _severity(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}
