import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../net/app_http_transport.dart';
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

/// The R8 mapping this Android build was made with
/// (docs/design/android-play-release.md §6, decision 135).
///
/// `tool/release_build.sh` gives every Android store build its own UUID and
/// prints the `sentry-cli upload-proguard` line that files the build's
/// `mapping.txt` under it. sentry_flutter copies this value into the Android
/// SDK on every start (`sentry_native_java_init.dart:237`, sentry_flutter
/// 10.5.0; line 219 in 9.26.0) — unconditionally, so a manifest key would be
/// erased by it — and
/// Sentry uses it to read Java and Kotlin frames that R8 renamed. Empty on
/// iOS, in debug runs and in every test.
const String _proguardUuid = String.fromEnvironment('SENTRY_PROGUARD_UUID');

/// `null` when no UUID was compiled in, never `""`: an empty string would
/// name a mapping that does not exist. Public so a test can hold both halves.
String? proguardUuidFrom(String define) => define.isEmpty ? null : define;

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
    await SentryFlutter.init(configureSentry);

    AppLogger.onError = (message, {error, stackTrace}) {
      Sentry.captureException(
        error ?? message,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setTag('logger_message', message),
      );
    };

    // Which network stack this process uses, on every event from here on —
    // and one message the first time Android falls back to dart:io
    // (docs/design/android-http3-transport.md §4.7).
    AppHttpTransport.instance.whenSettled(reportNetTransport);
  } catch (_) {
    // Reporting is best-effort. An app that will not start because its
    // telemetry failed to initialise is a worse outcome than a silent one.
  }
}

/// The tags every event carries once the transport has settled: `net.transport`
/// is `cronet` or `dartio`, and `net.fallback` names what made Cronet fail —
/// a class name, never a message or a URL. Public so a test can hold them.
Map<String, String> netTransportTags(NetTransportOutcome outcome) => {
  'net.transport': outcome.transport.name,
  'net.fallback': ?outcome.fallbackReason,
};

/// Sets [netTransportTags] on the scope, which sentry_flutter copies to the
/// native SDKs too, so a Java or native crash carries them as well. On a
/// fallback, also sends one message: it is how phones without Play Services,
/// or with a Cronet that fails to load, become visible (spec §4.7). Called once
/// per process, by [AppHttpTransport.whenSettled].
void reportNetTransport(NetTransportOutcome outcome) {
  final tags = netTransportTags(outcome);
  unawaited(
    Future.sync(
      () => Sentry.configureScope((scope) {
        for (final tag in tags.entries) {
          scope.setTag(tag.key, tag.value);
        }
      }),
    ),
  );
  if (outcome.isFallback) {
    unawaited(
      Sentry.captureMessage(
        'Android network fell back to dart:io',
        level: SentryLevel.warning,
        withScope: (scope) {
          for (final tag in tags.entries) {
            scope.setTag(tag.key, tag.value);
          }
        },
      ),
    );
  }
}

/// The options, as a NAMED function so a test can assert them.
///
/// **Extracted 2026-08-18.** They were an inline closure, and the only way to
/// inspect them afterwards was `Sentry.currentHub.options` — internal API the
/// analyzer refuses. So every guarantee below was stated in a comment and
/// verified by nothing: the same shape as the missing Apple entitlement and the
/// inert DSN, a promise with no mechanism behind it.
/// Held by `test/unit/error_reporting_test.dart`.
///
/// [proguardUuid] is the compiled-in define; a test passes one to see that it
/// reaches the options, which a run without the define cannot show (absent and
/// unwired both read `null`).
void configureSentry(
  SentryFlutterOptions options, {
  String proguardUuid = _proguardUuid,
}) {
  options
    ..dsn = _dsn
    ..environment = _environment
    // Android store builds only; null everywhere else (see [proguardUuidFrom]).
    ..proguardUuid = proguardUuidFrom(proguardUuid)
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
    // Off by default in the SDK, and set anyway: a default can change, and
    // the risk it guards against does not. (No longer marked experimental
    // since sentry_flutter 10.)
    ..attachViewHierarchy = false
    // **No release-health sessions.** The SDK defaults this to true, which
    // sends a session envelope on EVERY launch — data leaving the phone when
    // nothing has failed. The public privacy policy promises the opposite
    // (« Les fonctions de Sentry qui compteraient les visites ou les sessions
    // sont désactivées », web/app/politique-confidentialite), the web already
    // made this trade (browserSessionIntegration removed), and the App Store
    // privacy label must match what the binary does. The cost is the
    // crash-free-sessions rate; crashes themselves are still reported.
    ..enableAutoSessionTracking = false
    // App hangs stay ON, deliberately and explicitly: a hang is a failure,
    // reported only when one happens — inside the policy's « nothing is sent
    // when nothing has failed ». Declared on the App Store label as
    // Performance Data, not linked to the user (docs/design/app-store-forms.md).
    ..enableAppHangTracking = true
    ..beforeSend = (event, hint) => _scrub(event);
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
