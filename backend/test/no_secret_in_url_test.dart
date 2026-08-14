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
/// The two patterns, declared ONCE.
///
/// The first draft of this file re-declared them inside the "proven, not
/// assumed" test, which meant narrowing the live scan to silence a false
/// positive would leave the proof asserting against its own private copy — a
/// green test proving a regex nobody runs. Sharing them is the whole point.
final readPattern = RegExp(
  // `queryParameters` or `queryParametersAll` indexed by a credential-ish key,
  // or the raw `uri.query` parsed by hand.
  //
  // **Aliasing to a local first — `final q = ...queryParameters;` — was tried
  // and removed.** An adversarial pass was right that it bypasses this rule,
  // and adding it flagged FOURTEEN legitimate paginations and filters. A guard
  // that fires on correct code gets suppressed, and a suppressed guard is a
  // deleted one. It is recorded as a known gap below instead of pretended away.
  r'''queryParameters(?:All)?\s*\[\s*['"](secret|token|key|password|signature|sig|auth)['"]'''
  r'''|\.uri\.query\b(?!Parameters)''',
  caseSensitive: false,
);

/// Strips comments before scanning.
///
/// Without it, `cron_auth.dart` fails its own rule: its class documentation
/// quotes `queryParameters['secret']` to explain what was removed. Flagging a
/// file for *describing* the hazard is the fastest way to get a guard deleted.
/// Crude on purpose — `//` to end of line and `/* … */` — which is enough for a
/// rule about what code does, and stated rather than implied.
String stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

final urlPattern = RegExp(
  // A credential interpolated OR concatenated into a query string.
  r'''[?&](secret|token|key|password|sig|auth)=\s*(\$|'\s*\+|"\s*\+)''',
  caseSensitive: false,
);

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
    final pattern = readPattern;
    // `lib/` and `tool/` too, not just `routes/`. The auth logic this rule
    // protects now lives in `lib/` (`messaging/webhook_auth.dart`), which is
    // exactly where a future provider's query-signed callback would be read;
    // and `tool/` holds the smoke harness, which builds request URLs while
    // holding real secrets.
    for (final file in [
      ...dartFilesUnder('routes'),
      ...dartFilesUnder('lib'),
      ...dartFilesUnder('tool'),
    ]) {
      final source = stripComments(file.readAsStringSync());
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
    final pattern = urlPattern;
    for (final file in [
      ...dartFilesUnder('lib'),
      ...dartFilesUnder('routes'),
      ...dartFilesUnder('tool'),
    ]) {
      final source = stripComments(file.readAsStringSync());
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

  test('the scans can actually fail — proven against the SHARED patterns', () {
    // Every assertion above is "expect nothing", so a pattern that matches
    // nothing would make all of them permanently green. These exercise
    // `readPattern` and `urlPattern` themselves — the same objects the scans
    // use — so narrowing a live pattern breaks this test rather than quietly
    // hollowing out the guard.
    for (final line in [
      // Verbatim what this webhook used to do.
      "context.request.uri.queryParameters['secret']",
      // The variants an adversarial pass found bypassing the first draft.
      "context.request.uri.queryParametersAll['secret']?.first",
      "uri.queryParameters['token']",
      'final raw = context.request.uri.query;',
    ]) {
      expect(readPattern.hasMatch(line), isTrue, reason: line);
    }

    for (final line in [
      // Verbatim what the composition root used to build.
      r"'$publicBase/webhooks/messaging/status?secret=$messagingWebhookSecret'",
      r"'$base/webhooks/messaging/status?secret=' + secret",
      r"'$base/hook?token=$t'",
    ]) {
      expect(urlPattern.hasMatch(line), isTrue, reason: line);
    }
  });

  test('the patterns do not match ordinary, legitimate query use', () {
    // The other half of a useful pin: one that fires on `?page=2` gets
    // suppressed, and a suppressed guard is a deleted guard.
    for (final line in [
      "final page = context.request.uri.queryParameters['page'];",
      "uri.queryParameters['commune']",
      "queryParametersAll['category']",
      r"'$base/providers?page=$page'",
    ]) {
      expect(
        readPattern.hasMatch(line) || urlPattern.hasMatch(line),
        isFalse,
        reason: line,
      );
    }
  });

  test('what this pin does NOT catch, stated rather than implied', () {
    // The old pin claimed "no route can reintroduce it" and enforced two file
    // paths. Overclaiming is how it survived while being wrong, so: this is a
    // regex over source text. It catches the literal reintroduction and the
    // handful of near-spellings above. It does NOT catch a determined rewrite —
    // a key built by concatenation, a helper in another file, a manually parsed
    // query. Those cases are recorded here so the limit is reviewable.
    for (final knownBypass in [
      // Aliasing: removed from the rule because it flagged fourteen legitimate
      // paginations. This is the single most likely way the rule gets broken
      // again, and it is a gap, not a pass.
      'final q = context.request.uri.queryParameters; q[\'secret\'];',
      r"const k = 'sec' + 'ret'; uri.queryParameters[k]",
      'readCredentialFromSomewhereElse(context)',
    ]) {
      expect(
        readPattern.hasMatch(knownBypass),
        isFalse,
        reason: 'documented gap, not a passing grade: $knownBypass',
      );
    }
    // The durable answer is that the two mechanisms which *should* be used —
    // `CronAuth` and `MessagingWebhookAuth` — both take their credential as a
    // header or verify a signature, so a new route has a correct thing to copy.
    expect(File('lib/src/cron_auth.dart').existsSync(), isTrue);
    expect(File('lib/src/messaging/webhook_auth.dart').existsSync(), isTrue);
  });
}
