import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/logger.dart';

/// The single integration point between the app and error reporting
/// (docs/design/observability-error-reporting.md §6).
///
/// **What is and is not testable here, honestly.** `SentryFlutter.init` needs
/// platform channels and a DSN, so the SDK side belongs to a real build, not to
/// this suite. What *is* testable — and what actually matters — is the seam:
/// `AppLogger.error` must reach the hook, because `main.dart` funnels
/// `FlutterError.onError` and every uncaught async error through it. If that one
/// call is wrong, the whole slice is a dashboard that never receives anything,
/// which is precisely how the web wiring shipped dead for one commit.
void main() {
  tearDown(() => AppLogger.onError = null);

  test('AppLogger.error reaches the hook, with the error and the trace', () {
    final seen = <({String message, Object? error, StackTrace? stack})>[];
    AppLogger.onError = (message, {error, stackTrace}) =>
        seen.add((message: message, error: error, stack: stackTrace));

    final trace = StackTrace.current;
    AppLogger.error('booking failed', error: 'boom', stackTrace: trace);

    expect(seen, hasLength(1));
    expect(seen.single.message, 'booking failed');
    expect(seen.single.error, 'boom');
    expect(seen.single.stack, trace);
  });

  test('the other levels do NOT report — only error does', () {
    // Reporting a warning would make the signal noise, and noise is how a
    // dashboard stops being read.
    var calls = 0;
    AppLogger.onError = (_, {error, stackTrace}) => calls++;
    AppLogger.debug('d');
    AppLogger.info('i');
    AppLogger.warning('w');
    expect(calls, 0);
    AppLogger.error('e');
    expect(calls, 1);
  });

  test('no hook set → error() still logs and does not throw', () {
    // The default in every test and in any build without a DSN.
    AppLogger.onError = null;
    expect(() => AppLogger.error('no reporter attached'), returnsNormally);
  });

  test('a throwing hook cannot become the crash', () {
    // Reporting is best-effort by construction: an exception on the way out
    // must not propagate into the error path it was reporting on.
    AppLogger.onError = (_, {error, stackTrace}) =>
        throw StateError('the reporter itself failed');
    expect(() => AppLogger.error('original failure'), returnsNormally);
  });

  test('the hook is off by default, so the suite never reports', () {
    // Asserted rather than assumed: a hook left set by an earlier test would
    // silently attach reporting to every test after it.
    expect(AppLogger.onError, isNull);
  });
}
