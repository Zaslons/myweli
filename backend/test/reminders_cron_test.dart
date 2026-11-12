import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronAuth;
import 'package:myweli_backend/src/messaging/reminder_scheduler.dart';
import 'package:myweli_backend/src/messaging/reminders_cron.dart';
import 'package:test/test.dart';

import '../routes/internal/cron/reminders.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

/// `POST /internal/cron/reminders` since decision 133 (B0.18 —
/// docs/design/salon-go-live-approval.md §5.1): the 24h/2h reminders, then
/// the admin's place-change summaries that are due, on the same 15-minute
/// Scheduler tick — no job of its own.
void main() {
  final now = DateTime.utc(2026, 11, 12, 10);

  group('runRemindersCron — what the route answers once the cron door let '
      'the call in', () {
    test(
      'the reminders\' counts, and the summaries sent: placeChangeSummaries',
      () async {
        final body = await runRemindersCron(
          reminders: (_) async => (reminder24h: 3, reminder2h: 1),
          placeChangeSummaries: (_) async => 2,
          now: now,
        );
        expect(body, {
          'reminder24h': 3,
          'reminder2h': 1,
          'placeChangeSummaries': 2,
        });
      },
    );

    test('the reminders run FIRST, both at the same instant', () async {
      final order = <String>[];
      final seen = <DateTime>[];
      await runRemindersCron(
        reminders: (t) async {
          order.add('reminders');
          seen.add(t);
          return (reminder24h: 0, reminder2h: 0);
        },
        placeChangeSummaries: (t) async {
          order.add('summaries');
          seen.add(t);
          return 0;
        },
        now: now,
      );
      expect(order, ['reminders', 'summaries']);
      expect(seen, [now, now]);
    });

    test('A THROWING SUMMARY STEP never fails the reminders: their counts '
        'stand, the summaries read 0, the log says the step and the error '
        'type — nothing else', () async {
      final logs = <String>[];
      final body = await runRemindersCron(
        reminders: (_) async => (reminder24h: 4, reminder2h: 2),
        placeChangeSummaries: (_) async =>
            throw StateError('admin@myweli.com +2250700000009'),
        now: now,
        log: logs.add,
      );
      expect(body, {
        'reminder24h': 4,
        'reminder2h': 2,
        'placeChangeSummaries': 0,
      });
      expect(logs, [
        'cron_reminders step=place_change_summaries outcome=failed '
            'error=StateError',
      ]);
    });

    test('a failing REMINDERS step still fails the tick, as before — and the '
        'summaries do not run', () async {
      var summaries = 0;
      await expectLater(
        runRemindersCron(
          reminders: (_) async => throw StateError('db down'),
          placeChangeSummaries: (_) async => ++summaries,
          now: now,
        ),
        throwsStateError,
      );
      expect(summaries, 0);
    });
  });

  group('the route', () {
    RequestContext ctx(HttpMethod method) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          method.value,
          Uri.parse('http://localhost/internal/cron/reminders'),
        ),
      );
      return c;
    }

    test('a GET → 405, nothing read', () async {
      final c = ctx(HttpMethod.get);
      final res = await route.onRequest(c);
      expect(res.statusCode, HttpStatus.methodNotAllowed);
      verifyNever(() => c.read<ReminderScheduler>());
    });

    test('the door is unchanged: unconfigured (no OIDC pair, as here) → 404 '
        'before any tick', () async {
      expect(
        cronAuth.isConfigured,
        isFalse,
        reason: 'the test environment sets no CRON_OIDC_AUDIENCE',
      );
      final c = ctx(HttpMethod.post);
      final res = await route.onRequest(c);
      expect(res.statusCode, HttpStatus.notFound);
      verifyNever(() => c.read<ReminderScheduler>());
    });

    // Comments stripped first: the route's doc names what it calls.
    final code = File('routes/internal/cron/reminders.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    test('the tick runs only AFTER the cron door: configured, then '
        'authenticated', () {
      final configured = code.indexOf('cronAuth.isConfigured');
      final authenticated = code.indexOf('cronAuth.authenticate(');
      final denied = code.indexOf(
        "jsonError(HttpStatus.forbidden, 'forbidden')",
      );
      final tick = code.indexOf('runRemindersCron(');
      for (final i in [configured, authenticated, denied, tick]) {
        expect(i, isNonNegative);
      }
      expect(configured, lessThan(authenticated));
      expect(authenticated, lessThan(denied));
      expect(denied, lessThan(tick));
    });

    test('it composes the REAL reminders and the REAL summaries, the '
        'summaries read inside their own step', () {
      final flat = code.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains('reminders: context.read<ReminderScheduler>().tick,'),
      );
      expect(
        flat,
        contains(
          'placeChangeSummaries: (now) => '
          'context.read<SalonPlaceNoticeService>().tick(now),',
        ),
      );
    });
  });
}
