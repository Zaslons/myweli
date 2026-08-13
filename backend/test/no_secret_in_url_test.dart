import 'dart:io';

import 'package:test/test.dart';

/// **No credential may travel in a URL** (docs/BACKEND.md §7, T19 + T21).
///
/// ## Why this file exists rather than the pin it replaces
///
/// The rule was already pinned — and the pin missed a live violation for its
/// whole life. It sat in `cron_auth_test.dart` and read:
///
/// ```dart
/// for (final path in [
///   'routes/internal/cron/reminders.dart',
///   'routes/internal/cron/subscriptions.dart',
/// ]) { ... }
/// ```
///
/// Two file paths, enumerated by hand. `routes/webhooks/messaging/status.dart`
/// was authenticating on `?secret=` the entire time, and T21's claim that the
/// pattern was "source-pinned so no route can reintroduce it" was therefore
/// false as written: the pin protected the two routes someone remembered, not
/// the rule.
///
/// **An allowlist of the things you thought of is not a guard against the things
/// you did not.** So this walks the whole route tree, and the composition root
/// that builds the callback URLs, and requires zero matches with no exemptions.
/// A new route that reads a secret from the query fails here on the day it is
/// written, which is the only moment the fix is cheap.
///
/// Source-pinned rather than exercised, because these routes read composition-
/// root singletons built from `Platform.environment` at import time, so a
/// handler test cannot configure them in-process. The repo already uses this
/// shape for its design-system pins.
void main() {
  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('the route tree is not empty — the scan must not pass vacuously', () {
    // A directory walk that silently finds nothing is a green test that checks
    // nothing, which is the failure mode this whole file is about.
    final routes = dartFilesUnder('routes');
    expect(
      routes.length,
      greaterThan(20),
      reason:
          'expected to be scanning the real route tree, found '
          '${routes.length} files',
    );
  });

  test('NO route reads a secret from the query string', () {
    // `queryParameters` itself is legitimate — pagination, filters, search. The
    // rule is narrower and absolute: a *secret* never arrives that way, because
    // a URL is recorded by Cloud Run request logs, the load balancer, and any
    // proxy in between.
    final offenders = <String>[];
    final pattern = RegExp(
      r'''queryParameters\s*\[\s*['"](secret|token|key|password|signature)['"]\s*\]''',
      caseSensitive: false,
    );
    for (final file in dartFilesUnder('routes')) {
      final source = file.readAsStringSync();
      for (final m in pattern.allMatches(source)) {
        offenders.add('${file.path}: ${m.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a credential read from the query string lands in every log that '
          'records a URL. Send it as a header, or verify a request signature '
          '— see lib/src/cron_auth.dart and lib/src/messaging/webhook_auth.dart',
    );
  });

  test('NOTHING BUILDS a callback URL with a secret in the query', () {
    // The other half, and the half the old pin could never have caught: the
    // route stopped reading `?secret=` only because the composition root
    // stopped *sending* it. Checking one side without the other leaves the
    // credential in Twilio's stored configuration and in our own logs at the
    // moment the callback is registered.
    final offenders = <String>[];
    final pattern = RegExp(
      r'''[?&](secret|token|key|password)=\$''',
      caseSensitive: false,
    );
    for (final file in [
      ...dartFilesUnder('lib'),
      ...dartFilesUnder('routes'),
    ]) {
      final source = file.readAsStringSync();
      for (final m in pattern.allMatches(source)) {
        offenders.add('${file.path}: ${m.group(0)}…');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'interpolating a credential into a URL puts it in the logs of '
          'everyone who handles the request, and in the sender’s stored config',
    );
  });

  test('the scan can actually fail — proven, not assumed', () {
    // Every assertion above is "expect nothing". Without this, a regex that
    // matches nothing at all would make all three permanently green. Both
    // patterns are re-stated here against strings that must match.
    final queryPattern = RegExp(
      r'''queryParameters\s*\[\s*['"](secret|token|key|password|signature)['"]\s*\]''',
      caseSensitive: false,
    );
    expect(
      queryPattern.hasMatch("context.request.uri.queryParameters['secret']"),
      isTrue,
      reason: 'this is verbatim what the messaging webhook used to do',
    );

    final urlPattern = RegExp(
      r'''[?&](secret|token|key|password)=\$''',
      caseSensitive: false,
    );
    expect(
      urlPattern.hasMatch(
        r"'$publicBase/webhooks/messaging/status?secret=$messagingWebhookSecret'",
      ),
      isTrue,
      reason: 'this is verbatim what the composition root used to build',
    );
  });
}
