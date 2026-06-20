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

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.error, message, error: error, stackTrace: stackTrace);
    // TODO(observability): forward errors to Sentry/Crashlytics once a DSN /
    // Firebase project is configured. Keep this the single integration point.
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
