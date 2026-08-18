import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/observability/error_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Does the app actually turn Sentry ON when it is given a DSN?
///
/// ## Why this test and not a manual run
///
/// LAUNCH.md §5.2 asks us to "trigger one real error per surface and watch it
/// arrive". For the backend and the web that was a one-off, and it stayed
/// proven because both surfaces report continuously. A phone app has neither
/// property: nothing reports until someone builds a release with the define,
/// and a one-off simulator run proves only the build that was in front of you.
///
/// The failure this guards is specific and silent. `initErrorReporting` returns
/// early when the DSN is empty — deliberately, because telemetry that can break
/// the app is worse than no telemetry — so a build missing the define starts,
/// runs, looks perfect and reports nothing. That was the app's actual state for
/// weeks while `sentry_flutter` sat in the pubspec.
///
/// **Run with the define, which is the whole point:**
///
/// ```sh
/// flutter test test/unit/error_reporting_test.dart \
///   --dart-define=SENTRY_DSN=https://k@o1.ingest.de.sentry.io/2
/// ```
///
/// Without it the suite still passes — asserting the OTHER half of the
/// contract, that no DSN means no reporting. Both directions matter, and CI
/// exercises the second on every run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dsn = String.fromEnvironment('SENTRY_DSN');

  tearDown(() async {
    if (Sentry.isEnabled) await Sentry.close();
  });

  test('no DSN → reporting stays off, and nothing throws', () async {
    if (dsn.isNotEmpty) return; // the other branch owns this run
    await initErrorReporting();
    expect(
      Sentry.isEnabled,
      isFalse,
      reason:
          'an absent DSN must leave the SDK inert — dev, CI and every test run '
          'depend on it, and a crash reporter that breaks startup is worse '
          'than none',
    );
  });

  test('a DSN → the SDK actually comes up', () async {
    if (dsn.isEmpty) return; // run with --dart-define to exercise this
    await initErrorReporting();
    expect(
      Sentry.isEnabled,
      isTrue,
      reason: 'the define reached the build but the SDK did not come up',
    );
  });

  test('the options keep a booking form out of an error report', () async {
    // Asserted against a fresh options object rather than the live hub, which
    // is internal API. Every one of these is a default that could change under
    // us, which is why the code sets them explicitly — and why something has
    // to check that it still does.
    final o = SentryFlutterOptions();
    configureSentry(o);

    expect(
      o.sendDefaultPii,
      isFalse,
      reason:
          'the app handles names, phone numbers and booking details '
          'throughout; none of it belongs in an error report',
    );
    expect(
      o.attachScreenshot,
      isFalse,
      reason:
          'a screenshot of a booking form is a picture of someone name '
          'and phone number',
    );
    expect(
      o.tracesSampleRate,
      0.0,
      reason:
          'errors only — performance monitoring is a separate decision '
          'with its own bill',
    );
    expect(
      o.beforeSend,
      isNotNull,
      reason:
          'the scrubber must be attached, or every guarantee above is '
          'only as good as the SDK defaults',
    );
  });

  test('the scrubber drops user, breadcrumbs and request', () {
    // The security-critical half, and the least visible: if it is wrong,
    // names and phone numbers go to a third party and NOTHING notices.
    final o = SentryFlutterOptions();
    configureSentry(o);

    final event = SentryEvent(
      user: SentryUser(id: 'u1', email: 'someone@example.com'),
      breadcrumbs: [Breadcrumb(message: 'tapped Réserver at Salon X')],
      request: SentryRequest(url: 'https://api.myweli.com/me?token=abc'),
    );
    final scrubbed = o.beforeSend!(event, Hint()) as SentryEvent?;

    expect(scrubbed, isNotNull);
    expect(scrubbed!.user, isNull);
    expect(scrubbed.breadcrumbs, isNull);
    expect(scrubbed.request, isNull);
  });
}
