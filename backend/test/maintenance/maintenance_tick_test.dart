import 'package:myweli_backend/src/maintenance/maintenance_tick.dart';
import 'package:test/test.dart';

/// The daily housekeeping, off the subscriptions cron
/// (docs/design/infra-cron-maintenance.md §2.1): the four tasks run in
/// today's order, each once, and their counts come out as they came — a
/// failed prune is a `null`, never a guess; a demo reset that throws makes the
/// tick throw (a 500 the cron alert sees, as before the move).
void main() {
  final calls = <String>[];
  late DateTime? resetAt;

  setUp(() {
    calls.clear();
    resetAt = null;
  });

  MaintenanceTick tick({
    int? throttle = 3,
    int? windows = 40,
    int? keys = 7,
    String demo = 'not_due',
    bool demoThrows = false,
  }) => MaintenanceTick(
    pruneThrottle: () async {
      calls.add('throttle');
      return throttle;
    },
    pruneRateLimits: () async {
      calls.add('windows');
      return windows;
    },
    pruneIdempotency: () async {
      calls.add('keys');
      return keys;
    },
    demoReset: (now) async {
      calls.add('demo');
      resetAt = now;
      if (demoThrows) throw StateError('snapshot unreadable');
      return demo;
    },
  );

  test('the four tasks, in order, each once — and their four counts', () async {
    final now = DateTime.utc(2026, 10, 22, 3, 30);
    final body = await tick(demo: 'ran').run(now);
    expect(calls, ['throttle', 'windows', 'keys', 'demo']);
    expect(body, {
      'throttleRowsPruned': 3,
      'rateLimitWindowsPruned': 40,
      'idempotencyKeysPruned': 7,
      'demoReset': 'ran',
    });
    expect(resetAt, now, reason: 'the reset is judged at the tick’s instant');
  });

  test('a prune that failed stays a null — the others still run', () async {
    final body = await tick(windows: null, keys: null).run(DateTime.utc(2026));
    expect(calls, ['throttle', 'windows', 'keys', 'demo']);
    expect(body['rateLimitWindowsPruned'], isNull);
    expect(body['idempotencyKeysPruned'], isNull);
    expect(body.containsKey('rateLimitWindowsPruned'), isTrue);
    expect(body['throttleRowsPruned'], 3);
  });

  // docs/design/backend-integrity-batch6.md §2.9 (B6.9): `false` said both
  // « not the day » and « refused » — the second is the demo identity lost.
  test('the demo reset says why it did not run', () async {
    for (final why in ['not_due', 'no_snapshot', 'refused:not_demo_owned']) {
      final body = await tick(demo: why).run(DateTime.utc(2026));
      expect(body['demoReset'], why);
    }
  });

  test('a demo reset that throws makes the tick throw (the alert sees it)', () {
    expect(tick(demoThrows: true).run(DateTime.utc(2026)), throwsStateError);
  });
}
