import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// What `ProJournalProvider` gained: `bookingCreated`, the quiet reload behind
/// it, and « only the newest request's answer is applied »
/// (docs/design/pro-journal-shows-new-booking.md §2.4, §5).
///
/// The fake answers like a server: **what it says is decided when the request
/// arrives**, and may be delivered later. That is the whole point of the
/// ordering cases — an answer computed before a booking existed, landing after
/// the booking is on screen.
class _Server extends MockProService {
  /// What the server holds, per salon.
  final Map<String, List<Appointment>> salons = {};
  List<JournalArtist> artists = const [];

  /// Every journal request, in the order it arrived.
  final List<_Request> requests = [];

  /// While true, answers wait for `release()`.
  bool hold = false;

  /// How the NEXT requests are answered: null = the day, else 'error',
  /// 'forbidden' or 'throw'.
  String? failure;

  void reset() {
    salons.clear();
    artists = const [];
    requests.clear();
    hold = false;
    failure = null;
  }

  List<Appointment> of(String providerId) =>
      salons.putIfAbsent(providerId, () => []);

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) {
    final key = salonDayKey(date);
    final failure = this.failure;
    // Decided NOW, as a server decides on arrival.
    final ApiResponse<JournalDay> Function() answer = switch (failure) {
      'throw' => () => throw Exception('SocketException'),
      'error' => () => ApiResponse.error('Erreur réseau. Réessayez.'),
      'forbidden' => () => ApiResponse.error('Accès refusé', code: 'forbidden'),
      _ => () {
        final day = JournalDay(
          date: key,
          artists: artists,
          appointments: [
            for (final a in of(providerId))
              if (salonDayKey(a.appointmentDate) == key) a,
          ],
        );
        return () => ApiResponse.success(day);
      }(),
    };
    final request = _Request(providerId, key, answer);
    requests.add(request);
    if (!hold) request.release();
    return request.done.future;
  }
}

class _Request {
  _Request(this.providerId, this.day, this._answer);

  final String providerId;
  final String day;
  final ApiResponse<JournalDay> Function() _answer;
  final done = Completer<ApiResponse<JournalDay>>();

  void release() {
    if (done.isCompleted) return;
    try {
      done.complete(_answer());
    } catch (e, st) {
      done.completeError(e, st);
    }
  }
}

void main() {
  final server = _Server();

  // Monday 13 July 2026 — the displayed week is 13–19 July.
  final monday = DateTime.utc(2026, 7, 13);

  setUpAll(() {
    serviceLocator.proService = server; // late final — one fake for the file
  });
  setUp(server.reset);

  Appointment appt({
    required String id,
    String time = '10:00',
    int day = 13,
    String? artistId,
    String providerId = 'p1',
    String? displayName,
    String status = 'confirmed',
  }) => Appointment(
    id: id,
    userId: id.startsWith('m') ? 'manual' : 'u1',
    providerId: providerId,
    serviceIds: const ['s1'],
    artistId: artistId,
    appointmentDate: DateTime.parse('2026-07-${day}T$time:00.000Z'),
    status: AppointmentStatus.values.byName(status),
    totalPrice: 10000,
    durationMinutes: 60,
    clientDisplayName: displayName,
    createdAt: DateTime.parse('2026-07-13T08:00:00.000Z'),
  );

  /// A provider with the day loaded and the week prefetch finished.
  Future<ProJournalProvider> opened({String? tz}) async {
    final p = ProJournalProvider();
    addTearDown(p.dispose);
    await p.load('p1', date: monday, tz: tz);
    await pumpEventQueue();
    return p;
  }

  /// Drains the quiet reload and the week prefetch behind it.
  Future<void> settled() => pumpEventQueue();

  Iterable<String> shown(ProJournalProvider p) =>
      p.visibleAppointments.map((a) => a.id);

  group('bookingCreated — the displayed day', () {
    test('the booking is in the day AT ONCE, in time order, with no loader '
        'and one quiet request', () async {
      server.of('p1').addAll([
        appt(id: 'a1', time: '09:00'),
        appt(id: 'a2', time: '14:00'),
      ]);
      final p = await opened();
      final requestsBefore = server.requests.length;
      var notified = 0;
      final loadingSeen = <bool>[];
      p.addListener(() {
        notified++;
        loadingSeen.add(p.isLoading);
      });

      server.hold = true; // the reload cannot answer
      final created = appt(id: 'm1', time: '11:00');
      server.of('p1').add(created);
      p.bookingCreated(created);

      // Synchronously — before any answer could have arrived.
      expect(shown(p), ['a1', 'm1', 'a2']);
      expect(notified, 1);
      expect(p.isLoading, isFalse);
      expect(p.error, isNull);
      expect(p.weekCounts['2026-07-13'], 3);
      expect(server.requests.length, requestsBefore + 1);
      expect(server.requests.last.day, '2026-07-13');

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();
      expect(shown(p), ['a1', 'm1', 'a2']);
      expect(loadingSeen, everyElement(isFalse), reason: 'never a loader');
      expect(p.error, isNull);
    });

    test('the server answers, and what it says wins', () async {
      server.of('p1').add(appt(id: 'a1', time: '09:00'));
      final p = await opened();

      // The server holds its own version of the booking — the client's name
      // from the salon's records — and one more, taken on another device.
      server.of('p1').addAll([
        appt(id: 'm1', time: '11:00', displayName: 'Yao Kouamé'),
        appt(id: 'a9', time: '16:00'),
      ]);
      server.hold = true;
      p.bookingCreated(appt(id: 'm1', time: '11:00')); // the `201` body
      expect(shown(p), ['a1', 'm1']);
      expect(p.visibleAppointments.last.clientDisplayName, isNull);

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();

      expect(shown(p), ['a1', 'm1', 'a9']);
      expect(
        p.visibleAppointments.firstWhere((a) => a.id == 'm1').clientDisplayName,
        'Yao Kouamé',
      );
      expect(p.weekCounts['2026-07-13'], 3, reason: 'the server’s count');
    });

    test('a reload that comes back WITHOUT the booking removes it — it was '
        'asked after the booking existed, so the server means it', () async {
      server.of('p1').add(appt(id: 'a1', time: '09:00'));
      final p = await opened();

      // The server does not hold m1 (cancelled meanwhile, say).
      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      expect(shown(p), ['a1', 'm1']);
      await settled();
      expect(shown(p), ['a1']);
      expect(p.weekCounts['2026-07-13'], 1);
    });

    for (final failure in ['error', 'throw']) {
      test('the reload fails ($failure): the booking stays, no error, no '
          'loader, the day is not dropped', () async {
        server.of('p1').add(appt(id: 'a1', time: '09:00'));
        final p = await opened();
        final loadingSeen = <bool>[];
        p.addListener(() => loadingSeen.add(p.isLoading));

        server.failure = failure;
        p.bookingCreated(appt(id: 'm1', time: '11:00'));
        await settled();

        expect(shown(p), ['a1', 'm1']);
        expect(p.day, isNotNull);
        expect(p.error, isNull);
        expect(p.isLoading, isFalse);
        expect(loadingSeen, everyElement(isFalse));
        expect(p.weekCounts['2026-07-13'], 2, reason: 'the dot stays too');
      });
    }

    test('a refused reload still reports `forbidden` to the access seam — '
        'quiet for the salon, not for a revoked member', () async {
      final p = await opened();
      var probes = 0;
      final previous = ProAccessGuard.onForbidden;
      ProAccessGuard.onForbidden = () async => probes++;
      addTearDown(() => ProAccessGuard.onForbidden = previous);

      server.failure = 'forbidden';
      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      await settled();

      expect(probes, 1);
      expect(p.error, isNull);
      expect(shown(p), ['m1']);
    });

    test('announced twice: added once, counted once, one reload', () async {
      final p = await opened();
      server.hold = true;
      final created = appt(id: 'm1', time: '11:00');
      final requestsBefore = server.requests.length;

      p.bookingCreated(created);
      p.bookingCreated(created);

      expect(shown(p), ['m1']);
      expect(p.weekCounts['2026-07-13'], 1);
      expect(server.requests.length, requestsBefore + 1);
    });

    test('an empty day takes it too', () async {
      final p = await opened();
      expect(p.visibleAppointments, isEmpty);
      server.hold = true;
      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      expect(shown(p), ['m1']);
    });
  });

  group('bookingCreated — filters', () {
    test('the artist filter applies to it like to any row', () async {
      server.artists = const [JournalArtist(id: 'ar1', name: 'Awa')];
      server.of('p1').add(appt(id: 'a1', time: '09:00', artistId: 'ar1'));
      final p = await opened();
      p.setArtistFilter('ar1');
      expect(p.hasUnassigned, isFalse);
      server.hold = true;

      p.bookingCreated(appt(id: 'm1', time: '11:00')); // nobody's
      expect(shown(p), ['a1'], reason: 'the filter is « Awa »');
      expect(p.artistFilter, 'ar1', reason: 'the filter is not reset');
      expect(p.hasUnassigned, isTrue, reason: '« Sans artiste » appears');

      p.bookingCreated(appt(id: 'm2', time: '12:00', artistId: 'ar1'));
      expect(shown(p), ['a1', 'm2']);

      p.setArtistFilter('');
      expect(shown(p), ['m1']);
    });

    test('« Voir les annulés » is left as it was', () async {
      server.of('p1').add(appt(id: 'c1', time: '09:00', status: 'cancelled'));
      final p = await opened();
      expect(p.showCancelled, isFalse);
      server.hold = true;

      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      expect(p.showCancelled, isFalse);
      expect(shown(p), ['m1']);
    });
  });

  group('bookingCreated — another day', () {
    test('the displayed day and date do not change; the other day gets its '
        'dot at once; the day is still reloaded', () async {
      server.of('p1').add(appt(id: 'a1', time: '09:00'));
      final p = await opened();
      expect(p.weekCounts['2026-07-15'], 0);
      final requestsBefore = server.requests.length;
      server.hold = true;

      p.bookingCreated(appt(id: 'm1', time: '11:00', day: 15));

      expect(p.selectedDate, monday);
      expect(shown(p), ['a1']);
      expect(p.weekCounts['2026-07-15'], 1);
      expect(p.weekCounts['2026-07-13'], 1);
      expect(server.requests.length, requestsBefore + 1);
      expect(server.requests.last.day, '2026-07-13');
    });

    test('the salon timezone decides which day it is', () async {
      // 23:30 UTC on the 13th is the 14th in Libreville (UTC+1).
      final p = await opened(tz: 'Africa/Libreville');
      server.hold = true;
      p.bookingCreated(appt(id: 'm1', time: '23:30'));
      expect(shown(p), isEmpty);
      expect(p.weekCounts['2026-07-14'], 1);
    });

    test(
      'a count asked BEFORE the booking existed cannot overwrite its dot',
      () async {
        final p = ProJournalProvider();
        addTearDown(p.dispose);
        await p.load('p1', date: monday); // the day; the week prefetch starts
        // Hold the prefetch on whichever day it asks about next.
        server.hold = true;
        await pumpEventQueue();
        final prefetch = server.requests.last;
        expect(prefetch.done.isCompleted, isFalse);
        expect(prefetch.day, isNot('2026-07-13'));
        final dayOfMonth = int.parse(prefetch.day.substring(8));

        // The booking lands on exactly the day that request is asking about.
        final created = appt(id: 'm1', time: '11:00', day: dayOfMonth);
        server.of('p1').add(created);
        p.bookingCreated(created);
        expect(p.weekCounts[prefetch.day], 1);

        // Its answer — 0, decided before the booking — arrives now.
        prefetch.release();
        await pumpEventQueue();
        expect(p.weekCounts[prefetch.day], 1, reason: 'not written back to 0');

        server.hold = false;
        for (final r in server.requests) {
          r.release();
        }
        await settled();
        expect(p.weekCounts[prefetch.day], 1, reason: 'the server agrees');
      },
    );
  });

  group('bookingCreated — nothing to keep right', () {
    test('before « Ma journée » was ever opened: nothing is asked, nothing '
        'is stored', () async {
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      var notified = 0;
      p.addListener(() => notified++);

      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      await settled();

      expect(server.requests, isEmpty);
      expect(notified, 0);
      expect(p.weekCounts, isEmpty);
      expect(p.day, isNull);
    });

    test('another salon’s booking is ignored', () async {
      final p = await opened();
      final requestsBefore = server.requests.length;
      p.bookingCreated(appt(id: 'm1', time: '11:00', providerId: 'p2'));
      await settled();
      expect(shown(p), isEmpty);
      expect(server.requests.length, requestsBefore);
    });

    test(
      'after a salon switch: ignored until the new salon is loaded',
      () async {
        final p = await opened();
        p.resetForSalonSwitch();
        final requestsBefore = server.requests.length;
        p.bookingCreated(appt(id: 'm1', time: '11:00'));
        await settled();
        expect(server.requests.length, requestsBefore);
        expect(p.day, isNull);
      },
    );
  });

  group('bookingCreated — no settled day to add a row to', () {
    test('the day is still loading: it is asked for again, and the answer '
        'decided before the booking is dropped', () async {
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      server.hold = true;
      unawaited(p.load('p1', date: monday));
      expect(p.isLoading, isTrue);
      final first = server.requests.single; // decided: an empty day

      final created = appt(id: 'm1', time: '11:00');
      server.of('p1').add(created);
      p.bookingCreated(created);
      expect(server.requests, hasLength(2));
      expect(p.isLoading, isTrue);
      expect(p.day, isNull);

      // The old answer lands first: it must not paint an empty day.
      first.release();
      await pumpEventQueue();
      expect(p.day, isNull);
      expect(p.isLoading, isTrue, reason: 'the newer request owns the state');

      server.requests[1].release();
      server.hold = false;
      await settled();
      expect(p.isLoading, isFalse);
      expect(shown(p), ['m1']);
    });

    test('a pull-to-refresh was in flight, rows on screen: no row is added '
        'to them, the day is asked for again — and `isLoading` is not left '
        'raised by the answer that gets dropped', () async {
      server.of('p1').add(appt(id: 'a1', time: '09:00'));
      final p = await opened();
      server.hold = true;
      unawaited(p.refresh()); // decided: a1 only
      expect(p.isLoading, isTrue);
      expect(p.day, isNotNull);
      final requestsBefore = server.requests.length;

      final created = appt(id: 'm1', time: '11:00');
      server.of('p1').add(created);
      p.bookingCreated(created);
      expect(shown(p), [
        'a1',
      ], reason: 'not added to rows about to be replaced');
      expect(server.requests.length, requestsBefore + 1);

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();
      expect(p.isLoading, isFalse);
      expect(shown(p), ['a1', 'm1']);
      expect(p.error, isNull);
    });

    test('the day had failed: it is loaded again the ordinary way', () async {
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      server.failure = 'error';
      await p.load('p1', date: monday);
      expect(p.day, isNull);
      expect(p.error, isNotNull);

      server.failure = null;
      final created = appt(id: 'm1', time: '11:00');
      server.of('p1').add(created);
      p.bookingCreated(created);
      expect(p.isLoading, isTrue);
      await settled();

      expect(p.error, isNull);
      expect(shown(p), ['m1']);
    });

    test('…and when that load fails too, the error state is the ordinary '
        'one — there is no day to keep', () async {
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      server.failure = 'error';
      await p.load('p1', date: monday);

      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      await settled();
      expect(p.day, isNull);
      expect(p.error, isNotNull);
      expect(p.isLoading, isFalse);
    });
  });

  group('only the newest request’s answer is applied', () {
    test(
      'a pull-to-refresh after the booking outdates the quiet reload',
      () async {
        server.of('p1').add(appt(id: 'a1', time: '09:00'));
        final p = await opened();
        server.hold = true;

        p.bookingCreated(appt(id: 'm1', time: '11:00'));
        final quiet = server.requests.last; // decided: a1 only — no m1
        // The server now holds it, and the salon pulls the list down.
        server.of('p1').add(appt(id: 'm1', time: '11:00', displayName: 'Yao'));
        unawaited(p.refresh());
        final loud = server.requests.last;
        expect(loud, isNot(same(quiet)));

        loud.release();
        await pumpEventQueue();
        expect(shown(p), ['a1', 'm1']);

        // The quiet reload answers LAST, with a day that has no m1.
        quiet.release();
        await pumpEventQueue();
        expect(shown(p), ['a1', 'm1'], reason: 'an outdated answer is ignored');

        server.hold = false;
        for (final r in server.requests) {
          r.release();
        }
        await settled();
      },
    );

    test('two quick day changes: the slower, older day does not land under '
        'the newer date', () async {
      server.of('p1').addAll([
        appt(id: 'mon', time: '09:00', day: 13),
        appt(id: 'tue', time: '09:00', day: 14),
      ]);
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      server.hold = true;
      unawaited(p.load('p1', date: monday));
      final first = server.requests.last;
      unawaited(p.load('p1', date: DateTime.utc(2026, 7, 14)));
      final second = server.requests.last;

      second.release();
      await pumpEventQueue();
      expect(shown(p), ['tue']);

      first.release();
      await pumpEventQueue();
      expect(p.selectedDate, DateTime.utc(2026, 7, 14));
      expect(shown(p), ['tue'], reason: 'Monday’s rows under Tuesday’s date');
      expect(p.isLoading, isFalse);

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();
    });

    test('a salon switch drops the quiet reload in flight', () async {
      server.of('p1').add(appt(id: 'a1', time: '09:00'));
      final p = await opened();
      server.hold = true;
      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      final quiet = server.requests.last;

      p.resetForSalonSwitch();
      expect(p.day, isNull);
      quiet.release();
      await pumpEventQueue();
      expect(p.day, isNull, reason: 'the previous salon’s day');
      expect(p.weekCounts, isEmpty);
    });
  });
}
