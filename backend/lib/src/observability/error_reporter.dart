import 'package:sentry/sentry.dart';

import '../boot_config.dart';

/// Reports an unhandled error to whatever is watching (docs/design/
/// observability-error-reporting.md §4).
///
/// An interface with a no-op implementation, following the repository idiom, for
/// two reasons: tests must not need a network, and **an unconfigured deployment
/// must still boot**. `SENTRY_DSN` is deliberately NOT on the `guardsOn`
/// fail-fast list — an unreportable error is bad, but a backend that refuses to
/// start because its telemetry is unconfigured is worse.
abstract interface class ErrorReporter {
  /// Never throws and never blocks the response. A reporter that can take down
  /// a request is worse than no reporter.
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? requestId,
    String? method,
    String? path,
  });
}

/// The default when `SENTRY_DSN` is unset — dev, CI, and any deployment that
/// has not been given a DSN.
class NoopErrorReporter implements ErrorReporter {
  const NoopErrorReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? requestId,
    String? method,
    String? path,
  }) async {}
}

/// Sends to Sentry, with everything sensitive stripped first.
///
/// **The scrubbing is the security-critical part of this file.** Sentry's
/// `sendDefaultPii` already defaults to false, but this does not rely on that:
/// [scrubEvent] removes request bodies, headers, cookies and query strings
/// explicitly, so a future SDK default or a stray `Scope` addition cannot
/// quietly start shipping OTP codes and phone numbers to a third party.
class SentryErrorReporter implements ErrorReporter {
  const SentryErrorReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? requestId,
    String? method,
    String? path,
  }) async {
    try {
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          if (requestId != null) scope.setTag('request_id', requestId);
          // Method and path are route shape, not user data. The path may embed
          // an id (`/providers/provider3`), which is not PII — it identifies a
          // salon, not a person.
          if (method != null) scope.setTag('http_method', method);
          if (path != null) scope.setTag('http_path', path);
        },
      );
    } catch (_) {
      // Reporting must never become the failure. Swallowed on purpose.
    }
  }
}

/// Strips everything that must not leave the process
/// (docs/design/observability-error-reporting.md §4.2).
///
/// Written as a pure function on the event rather than inline in the SDK
/// callback so it can be tested directly — which matters, because the cost of
/// getting it wrong is silently shipping credentials and PII to a third party,
/// and nothing else in the system would notice.
SentryEvent? scrubEvent(SentryEvent event) {
  final req = event.request;
  if (req != null) {
    // Rebuilt from an allowlist rather than edited field by field — an
    // allowlist stays correct when the SDK adds a field, a blocklist silently
    // does not.
    event.request = SentryRequest(
      method: req.method,
      // The URL is kept, the query string is NOT: `?secret=` is gone (#352),
      // but the class of mistake outlives any single instance of it.
      url: req.url,
      // Bodies carry OTP codes, phone numbers, names and deposit references.
      // There is no "just the useful fields" that stays safe as routes are
      // added, so the whole thing goes.
      data: null,
      queryString: null,
      cookies: null,
      headers: const {},
    );
  }

  // Nothing sets these today, and that is exactly why they are cleared here:
  // the guarantee should hold for the code someone writes next year, not only
  // for the code that exists now.
  event.user = null; // id / email / ip_address
  event.breadcrumbs = null; // arbitrary trail, whatever a caller put in it
  // Deprecated in the SDK, and scrubbed anyway: deprecated is not the same as
  // unused, and a field that still accepts free-form data still leaks it.
  // ignore: deprecated_member_use
  event.extra = null;

  // `contexts` is deliberately KEPT. It carries OS, runtime and app metadata —
  // no user data, and the most useful thing in the event once the request is
  // stripped. Clearing it would trade real debugging value for no privacy gain.
  // If a custom context is ever added, revisit this line rather than that one.
  return event;
}

/// Builds the reporter from env. `SENTRY_DSN` unset → [NoopErrorReporter].
///
/// [environment] separates staging noise from production release health, and is
/// the same `Env` the guards use — so the three environments stay one concept
/// rather than two vocabularies.
Future<ErrorReporter> initErrorReporter({
  required String? dsn,
  required Env environment,
  required String? release,
}) async {
  if (dsn == null || dsn.trim().isEmpty) return const NoopErrorReporter();
  await Sentry.init((options) {
    options
      ..dsn = dsn.trim()
      ..environment = environment.name
      ..release = release
      // Errors only. Performance monitoring is a separate decision with its own
      // cost (§9); shipping it on by accident is how telemetry bills surprise
      // people.
      ..tracesSampleRate = 0.0
      // Belt to `scrubEvent`'s braces — the SDK must not decide to enrich
      // events with user data on our behalf.
      ..sendDefaultPii = false
      ..beforeSend = (event, hint) => scrubEvent(event);
  });
  return const SentryErrorReporter();
}
