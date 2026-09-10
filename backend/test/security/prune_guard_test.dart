import 'package:myweli_backend/src/security/rate_limiter.dart';
import 'package:test/test.dart';

/// The daily prune rides on the subscriptions cron. A prune that throws must
/// become a reported `null`, never the cron's 500 — otherwise the demo reset
/// after it is skipped and the missed-cron alert pages for housekeeping.
///
/// Design: docs/design/infra-cloudflare-front-door.md §4 (review finding).
void main() {
  test('a prune that succeeds returns its count and logs nothing', () async {
    final lines = <String>[];
    final n = await pruneOrReport(() async => 42, log: lines.add);
    expect(n, 42);
    expect(lines, isEmpty);
  });

  test(
    'a prune that throws returns null and logs one greppable line',
    () async {
      final lines = <String>[];
      final n = await pruneOrReport(
        () async => throw StateError('DELETE FROM identity_rate_limits …'),
        log: lines.add,
      );
      expect(n, isNull);
      expect(lines, ['rate_limit_prune_failed type=StateError']);
      // The message may quote SQL; the type is enough to grep for.
      expect(lines.single, isNot(contains('DELETE')));
    },
  );
}
