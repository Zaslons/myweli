import 'package:sentry_flutter/sentry_flutter.dart';

import '../utils/logger.dart';

/// Build-time Sentry configuration, supplied via `--dart-define`.
///
/// Unset → **reporting stays off**, which is why the app runs with no setup in
/// dev, in CI and in every test. Same posture as the backend's `SENTRY_DSN` and
/// the web's `NEXT_PUBLIC_SENTRY_DSN`: telemetry that can break the app is worse
/// than no telemetry.
const String _dsn = String.fromEnvironment('SENTRY_DSN');

/// Which deployment the app is pointed at, so staging noise never pollutes
/// production's release health. Defaults to the API base's own default posture.
const String _environment = String.fromEnvironment(
  'SENTRY_ENV',
  defaultValue: 'development',
);

/// Starts error reporting and hands [AppLogger] somewhere to send errors
/// (docs/design/observability-error-reporting.md §6).
///
/// **This is the whole integration.** `main.dart` already routes
/// `FlutterError.onError` and every uncaught async error through
/// `runZonedGuarded` into `AppLogger.error`, so attaching one hook covers the
/// framework, the zone, and every explicit call site in the app — which is what
/// `logger.dart` was built for.
///
/// Returns without doing anything when no DSN was compiled in. Never throws:
/// a failure here must not stop the app from starting.
Future<void> initErrorReporting() async {
  if (_dsn.isEmpty) return;
  try {
    await SentryFlutter.init((options) {
      options
        ..dsn = _dsn
        ..environment = _environment
        // `release` is deliberately NOT set. SentryFlutter reads it from the
        // platform package info and produces `package@version+build` — exactly
        // the shape wanted, and the number LAUNCH.md §1.4's staged rollout is
        // watched on. Setting it by hand would mean depending on
        // package_info_plus to reproduce what the SDK already does, and drifting
        // from it the first time the format changes.
        //
        // Errors only. Performance monitoring is a separate decision with its
        // own cost; shipping it on by accident is how telemetry bills surprise
        // people.
        ..tracesSampleRate = 0.0
        // The app handles names, phone numbers and booking details throughout;
        // none of it belongs in an error report.
        ..sendDefaultPii = false
        // A screenshot or view hierarchy of a booking form is a picture of
        // someone's name and phone number. Set explicitly rather than trusting
        // a default that could change.
        ..attachScreenshot = false
        // Experimental in the SDK; the risk it guards against is not. Kept
        // explicit rather than trusting a default.
        // ignore: experimental_member_use
        ..attachViewHierarchy = false
        ..beforeSend = (event, hint) => _scrub(event);
    });

    AppLogger.onError = (message, {error, stackTrace}) {
      Sentry.captureException(
        error ?? message,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setTag('logger_message', message),
      );
    };
  } catch (_) {
    // Reporting is best-effort. An app that will not start because its
    // telemetry failed to initialise is a worse outcome than a silent one.
  }
}

/// Removes what must never leave the device.
///
/// The same allowlist discipline as the backend and web scrubbers — an
/// allowlist stays correct when the SDK adds a field, a blocklist silently does
/// not. Breadcrumbs go entirely: the booking flow's navigation and taps carry
/// salon names, client names and phone numbers, and there is no filter over
/// free-form strings that stays safe as screens are added.
SentryEvent? _scrub(SentryEvent event) {
  event.user = null;
  event.breadcrumbs = null;
  event.request = null;
  // Deprecated in the SDK, and cleared anyway: deprecated is not the same as
  // unused, and a field that still accepts free-form data still leaks it.
  // ignore: deprecated_member_use
  event.extra = null;
  // `contexts` is deliberately KEPT: device model, OS version and app build —
  // no user data, and the most useful thing in a mobile crash report. A crash
  // that only happens on Android 9 is invisible without it.
  return event;
}
