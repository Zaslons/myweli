import 'package:myweli_backend/src/boot_config.dart';
import 'package:myweli_backend/src/observability/error_reporter.dart';
import 'package:sentry/sentry.dart';

/// Proves error reporting actually reaches Sentry.
///
/// ```sh
/// dart run tool/verify_sentry.dart "$(gcloud secrets versions access latest \
///   --secret=SENTRY_DSN --project=myweli)"
/// ```
///
/// **Why this exists as a committed tool rather than a one-off.** Three separate
/// times in this project, observability wiring has looked correct and done
/// nothing: the backend reporter captured before it was configured (#359), the
/// web SDK config files that no build ever loaded (#360), and the deploy
/// workflow curling a URL that 404s by design (#357). Each was found by
/// inspecting the artifact rather than the source.
///
/// So: a way to ask "does an event actually arrive" that takes one command, and
/// that goes through **the real code path** — `initErrorReporter` and
/// `ErrorReporter.report`, exactly what `observabilityMiddleware` calls — rather
/// than through a raw `Sentry.captureException` that would prove only that
/// Sentry exists.
///
/// The event lands under release `local-verification` and environment `dev`, so
/// it is trivially distinguishable from a real production error.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/verify_sentry.dart <SENTRY_DSN>');
    return;
  }

  final reporter = await initErrorReporter(
    dsn: args.first,
    environment: Env.dev,
    release: 'local-verification',
  );

  // The assertion. A malformed or rejected DSN makes `Sentry.init` throw, which
  // `initErrorReporter` catches and downgrades to the no-op — so getting the
  // real implementation back is itself proof the DSN was accepted.
  print('reporter: ${reporter.runtimeType}');
  if (reporter is! SentryErrorReporter) {
    print('FAIL — fell back to NoopErrorReporter; the DSN was not accepted.');
    return;
  }

  await reporter.report(
    StateError('MyWeli backend wiring verification — safe to resolve'),
    StackTrace.current,
    requestId: 'local-verification',
    method: 'GET',
    path: '/verification',
  );

  // Without this the process exits before the event leaves — which would look
  // exactly like success.
  await Sentry.close();
  print('OK — event sent through the real code path. Confirm it in Sentry.');
}
