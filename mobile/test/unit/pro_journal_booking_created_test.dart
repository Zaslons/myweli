import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
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

  List<Appointment> of(SalonId providerId) =>
      salons.putIfAbsent(providerId, () => []);

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    SalonId providerId,
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

  final SalonId providerId;
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
    SalonId providerId = const SalonId('p1'),
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
    await p.load(SalonId('p1'), date: monday, tz: tz);
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
      server.of(SalonId('p1')).addAll([
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
      server.of(SalonId('p1')).add(created);
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
      server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
      final p = await opened();

      // The server holds its own version of the booking — the client's name
      // from the salon's records — and one more, taken on another device.
      server.of(SalonId('p1')).addAll([
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

    test('the server’s day reaches the screen when IT lands — not after the '
        'six requests of the week prefetch behind it', () async {
      server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
      final p = await opened();
      server
          .of(SalonId('p1'))
          .add(appt(id: 'm1', time: '11:00', displayName: 'Yao Kouamé'));
      server.hold = true;
      p.bookingCreated(appt(id: 'm1', time: '11:00')); // the `201` body
      final quiet = server.requests.last;
      var notified = 0;
      p.addListener(() => notified++);

      // Only the day's own answer is delivered.
      quiet.release();
      await pumpEventQueue();

      final prefetch = server.requests.last;
      expect(prefetch, isNot(same(quiet)), reason: 'the prefetch has started');
      expect(prefetch.done.isCompleted, isFalse, reason: '…and is held');
      expect(notified, 1, reason: 'the listeners were told already');
      expect(
        p.visibleAppointments.firstWhere((a) => a.id == 'm1').clientDisplayName,
        'Yao Kouamé',
      );

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();
    });

    test('a reload that comes back WITHOUT the booking removes it — it was '
        'asked after the booking existed, so the server means it', () async {
      server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
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
        server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
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
      server
          .of(SalonId('p1'))
          .add(appt(id: 'a1', time: '09:00', artistId: 'ar1'));
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
      server
          .of(SalonId('p1'))
          .add(appt(id: 'c1', time: '09:00', status: 'cancelled'));
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
      server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
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
        await p.load(
          SalonId('p1'),
          date: monday,
        ); // the day; the week prefetch starts
        // Hold the prefetch on whichever day it asks about next.
        server.hold = true;
        await pumpEventQueue();
        final prefetch = server.requests.last;
        expect(prefetch.done.isCompleted, isFalse);
        expect(prefetch.day, isNot('2026-07-13'));
        final dayOfMonth = int.parse(prefetch.day.substring(8));

        // The booking lands on exactly the day that request is asking about.
        final created = appt(id: 'm1', time: '11:00', day: dayOfMonth);
        server.of(SalonId('p1')).add(created);
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
      p.bookingCreated(
        appt(id: 'm1', time: '11:00', providerId: SalonId('p2')),
      );
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
      unawaited(p.load(SalonId('p1'), date: monday));
      expect(p.isLoading, isTrue);
      final first = server.requests.single; // decided: an empty day

      final created = appt(id: 'm1', time: '11:00');
      server.of(SalonId('p1')).add(created);
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

    test('a day CHANGE is in flight — the rows on screen are another date’s: '
        'no row is added to them, even for a booking on the date being '
        'loaded; that date is asked for again the ordinary way', () async {
      server.of(SalonId('p1')).add(appt(id: 'mon', time: '09:00'));
      final p = await opened(); // Monday the 13th
      server.hold = true;
      final tuesday = DateTime.utc(2026, 7, 14);
      p.setDate(tuesday); // decided: an empty Tuesday
      final change = server.requests.last;
      expect(p.selectedDate, tuesday);
      expect(shown(p), ['mon'], reason: 'Monday’s rows, until Tuesday lands');
      expect(p.isLoading, isTrue);
      final requestsBefore = server.requests.length;

      // The booking is for Tuesday — the SELECTED date, not the rows’ date.
      final created = appt(id: 'm1', time: '11:00', day: 14);
      server.of(SalonId('p1')).add(created);
      p.bookingCreated(created);

      expect(shown(p), ['mon'], reason: 'not put among Monday’s rows');
      expect(p.isLoading, isTrue);
      expect(p.weekCounts['2026-07-14'], 1);
      expect(server.requests.length, requestsBefore + 1);
      expect(server.requests.last.day, '2026-07-14');

      // The day change’s own answer — Tuesday without the booking — is late.
      server.requests.last.release();
      await pumpEventQueue();
      expect(shown(p), ['m1']);
      expect(p.isLoading, isFalse);
      change.release();
      await pumpEventQueue();
      expect(shown(p), ['m1'], reason: 'an outdated answer is ignored');

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();
      expect(p.selectedDate, tuesday);
      expect(shown(p), ['m1']);
    });

    test('the day had failed: it is loaded again the ordinary way', () async {
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      server.failure = 'error';
      await p.load(SalonId('p1'), date: monday);
      expect(p.day, isNull);
      expect(p.error, isNotNull);

      server.failure = null;
      final created = appt(id: 'm1', time: '11:00');
      server.of(SalonId('p1')).add(created);
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
      server.failure = 'throw';
      await p.load(SalonId('p1'), date: monday);
      await settled(); // the week prefetch behind the failed load
      // The generic sentence — never the exception's own text
      // (docs/design/app-failure-messages.md §1.1).
      expect(p.error, 'Une erreur est survenue. Réessayez.');
      final requestsBefore = server.requests.length;

      // It DID try: one more request for the day, a loader meanwhile, and the
      // error shown afterwards is the new attempt's — not the one left over.
      server.failure = 'error';
      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      expect(p.isLoading, isTrue);
      expect(server.requests.length, requestsBefore + 1);
      expect(server.requests.last.day, '2026-07-13');
      await settled();
      expect(p.day, isNull);
      expect(p.error, 'Erreur réseau. Réessayez.');
      expect(p.isLoading, isFalse);
    });
  });

  group('bookingCreated — a refresh of the displayed day is in flight', () {
    // A pull-to-refresh, the refetch behind a swipe action, « Ma journée »
    // reopened: `isLoading` is raised, and the rows on screen ARE the selected
    // date's. The booking joins them at once, as on a settled day — the form
    // took longer to fill than the request has to answer only on a network
    // that is already failing, which is when a loud reload would cost the day.
    test(
      'the booking joins the rows at once; the flag the refresh raised is '
      'lowered; its answer, decided before the booking, is dropped',
      () async {
        server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
        final p = await opened();
        server.hold = true;
        unawaited(p.refresh()); // decided: a1 only
        final refresh = server.requests.last;
        expect(p.isLoading, isTrue);
        expect(p.day, isNotNull);
        final requestsBefore = server.requests.length;
        final loadingSeen = <bool>[];
        p.addListener(() => loadingSeen.add(p.isLoading));

        final created = appt(id: 'm1', time: '11:00');
        server.of(SalonId('p1')).add(created);
        p.bookingCreated(created);

        // Synchronously — nothing has answered.
        expect(shown(p), ['a1', 'm1']);
        expect(p.isLoading, isFalse, reason: 'nobody else would lower it');
        expect(loadingSeen, [false]);
        expect(p.error, isNull);
        expect(p.weekCounts['2026-07-13'], 2);
        expect(server.requests.length, requestsBefore + 1);
        final quiet = server.requests.last;
        expect(quiet.day, '2026-07-13');

        // The refresh answers first, with the day as it was before the booking.
        refresh.release();
        await pumpEventQueue();
        expect(shown(p), ['a1', 'm1'], reason: 'an outdated answer is ignored');
        expect(p.isLoading, isFalse);

        server.hold = false;
        for (final r in server.requests) {
          r.release();
        }
        await settled();
        expect(shown(p), ['a1', 'm1']);
        expect(p.isLoading, isFalse);
        expect(p.error, isNull);
        expect(loadingSeen, everyElement(isFalse), reason: 'never a loader');
      },
    );

    for (final failure in ['error', 'throw']) {
      test('…and both fail ($failure) — the refresh in flight and the reload '
          'behind the booking: the day and the booking stay, nothing is '
          'said', () async {
        server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
        final p = await opened();
        server.hold = true;
        server.failure = failure; // the network is going
        unawaited(p.refresh()); // decided: a failure
        final refresh = server.requests.last;

        p.bookingCreated(appt(id: 'm1', time: '11:00'));
        final quiet = server.requests.last; // decided: a failure
        expect(quiet, isNot(same(refresh)));
        expect(shown(p), ['a1', 'm1']);

        // The reload behind the booking fails first, the older refresh last.
        quiet.release();
        await pumpEventQueue();
        refresh.release();
        await pumpEventQueue();

        expect(p.day, isNotNull, reason: 'the day is not dropped');
        expect(shown(p), ['a1', 'm1']);
        expect(p.error, isNull, reason: 'no « Une erreur est survenue »');
        expect(p.isLoading, isFalse);
        expect(p.weekCounts['2026-07-13'], 2);
      });
    }

    test('« Ma journée » reopened (a load with no date): the same', () async {
      server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
      final p = await opened();
      server.hold = true;
      unawaited(p.load(SalonId('p1'))); // the screen's own `initState` load
      expect(p.selectedDate, monday);
      expect(p.isLoading, isTrue);

      p.bookingCreated(appt(id: 'm1', time: '11:00'));
      expect(shown(p), ['a1', 'm1']);
      expect(p.isLoading, isFalse);

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();
    });
  });

  group('only the newest request’s answer is applied', () {
    test(
      'a pull-to-refresh after the booking outdates the quiet reload',
      () async {
        server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
        final p = await opened();
        server.hold = true;

        p.bookingCreated(appt(id: 'm1', time: '11:00'));
        final quiet = server.requests.last; // decided: a1 only — no m1
        // The server now holds it, and the salon pulls the list down.
        server
            .of(SalonId('p1'))
            .add(appt(id: 'm1', time: '11:00', displayName: 'Yao'));
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
      server.of(SalonId('p1')).addAll([
        appt(id: 'mon', time: '09:00', day: 13),
        appt(id: 'tue', time: '09:00', day: 14),
      ]);
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      server.hold = true;
      unawaited(p.load(SalonId('p1'), date: monday));
      final first = server.requests.last;
      unawaited(p.load(SalonId('p1'), date: DateTime.utc(2026, 7, 14)));
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

    test('an older load that THROWS late — a socket that gives up after the '
        'newer answer is on screen — does not drop the day', () async {
      server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
      final p = await opened();
      server.hold = true;
      server.failure = 'throw';
      unawaited(p.refresh()); // decided: it will throw
      final older = server.requests.last;
      server.failure = null;
      server.of(SalonId('p1')).add(appt(id: 'a2', time: '14:00'));
      unawaited(p.refresh()); // decided: a1, a2
      final newer = server.requests.last;
      expect(newer, isNot(same(older)));

      newer.release();
      await pumpEventQueue();
      expect(shown(p), ['a1', 'a2']);
      expect(p.isLoading, isFalse);

      older.release();
      await pumpEventQueue();
      expect(p.day, isNotNull, reason: 'an outdated failure erased the day');
      expect(shown(p), ['a1', 'a2']);
      expect(p.error, isNull);
      expect(p.isLoading, isFalse);

      server.hold = false;
      for (final r in server.requests) {
        r.release();
      }
      await settled();
    });

    test('a salon switch drops the quiet reload in flight', () async {
      server.of(SalonId('p1')).add(appt(id: 'a1', time: '09:00'));
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

  // docs/design/web-pro-week-strip.md §6 (owner Q2, 2026-10-19): the week's
  // dots say the LOAD. The day hides its cancelled bookings by default, so a
  // day whose only booking was cancelled used to keep its dot and open empty.
  group('the week dots — cancelled bookings do not count', () {
    test('another day whose only booking was cancelled has no dot', () async {
      server.of(SalonId('p1')).addAll([
        appt(id: 'a1', time: '09:00'),
        appt(id: 'c1', day: 16, status: 'cancelled'),
        appt(id: 'f1', day: 17, status: 'pending'),
        appt(id: 'f2', day: 17, time: '11:00', status: 'cancelled'),
      ]);
      final p = await opened();
      expect(p.weekCounts['2026-07-16'] ?? 0, 0);
      expect(p.weekCounts['2026-07-17'], 1);
    });

    test('the displayed day counts its non-cancelled bookings', () async {
      server.of(SalonId('p1')).addAll([
        appt(id: 'a1', time: '09:00'),
        appt(id: 'a2', time: '11:00', status: 'cancelled'),
        appt(id: 'a3', time: '14:00', status: 'completed'),
      ]);
      final p = await opened();
      expect(p.weekCounts['2026-07-13'], 2);
    });
  });
}
