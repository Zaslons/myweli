import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// docs/design/app-pro-home-journal-fresh.md §2.1 (owner decision 8: every
/// screen that shows the booking, at once) — a booking whose status or time
/// changes is announced ONCE, after the server's success, and every store that
/// shows the salon's bookings applies it, then reloads quietly.
class _Server extends MockProService {
  final List<Appointment> bookings = [];
  int journalCalls = 0;
  int listCalls = 0;

  /// While set, journal answers wait for it.
  Completer<void>? journalGate;

  /// null = answers; 'error' = refusal; 'throw' = no answer at all.
  String? journalFailure;

  /// When set, every status write is refused.
  bool refuseWrites = false;

  void reset() {
    bookings.clear();
    journalCalls = 0;
    listCalls = 0;
    journalGate = null;
    journalFailure = null;
    refuseWrites = false;
  }

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async {
    journalCalls++;
    final failure = journalFailure;
    final key = salonDayKey(date);
    final snapshot = [
      for (final a in bookings)
        if (a.providerId == providerId && salonDayKey(a.appointmentDate) == key)
          a,
    ];
    final gate = journalGate;
    if (gate != null) await gate.future;
    if (failure == 'throw') throw Exception('SocketException');
    if (failure == 'error') return ApiResponse.error('Erreur réseau.');
    return ApiResponse.success(
      JournalDay(date: key, artists: const [], appointments: snapshot),
    );
  }

  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    listCalls++;
    return ApiResponse.success([
      for (final a in bookings)
        if (a.providerId == providerId) a,
    ]);
  }

  Future<ApiResponse<bool>> _write(
    String id,
    Appointment Function(Appointment) f,
  ) async {
    if (refuseWrites) {
      return ApiResponse.error('Refusé', code: 'invalid_transition');
    }
    final i = bookings.indexWhere((a) => a.id == id);
    if (i == -1) return ApiResponse.error('Introuvable', code: 'not_found');
    bookings[i] = f(bookings[i]);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> acceptAppointment(String appointmentId) => _write(
    appointmentId,
    (a) => a.copyWith(status: AppointmentStatus.confirmed),
  );

  @override
  Future<ApiResponse<bool>> rejectAppointment(
    String appointmentId,
    String? reason,
  ) => _write(
    appointmentId,
    (a) => a.copyWith(status: AppointmentStatus.cancelled),
  );

  @override
  Future<ApiResponse<bool>> markAppointmentComplete(String appointmentId) =>
      _write(
        appointmentId,
        (a) => a.copyWith(status: AppointmentStatus.completed),
      );

  @override
  Future<ApiResponse<bool>> markNoShow(String appointmentId) => _write(
    appointmentId,
    (a) => a.copyWith(status: AppointmentStatus.noShow),
  );

  @override
  Future<ApiResponse<bool>> markArrived(String appointmentId) => _write(
    appointmentId,
    (a) => a.copyWith(arrivedAt: DateTime.utc(2026, 7, 13, 9, 55)),
  );

  @override
  Future<ApiResponse<bool>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  ) => _write(appointmentId, (a) => a.copyWith(appointmentDate: newDateTime));
}

/// A store that only records what it hears.
class _Ear extends ChangeNotifier implements HearsBookingChanges {
  final heard = <BookingChange>[];
  bool explode = false;

  @override
  void bookingChanged(BookingChange change) {
    if (explode) throw StateError('boom');
    heard.add(change);
  }

  @override
  void resetForSalonSwitch() {}
}

/// A store that keeps a salon's state but shows no bookings.
class _Deaf extends ChangeNotifier implements SalonScoped {
  @override
  void resetForSalonSwitch() {}
}

void main() {
  final server = _Server();

  setUpAll(() {
    serviceLocator.proService = server; // late final — one fake for the file
  });
  setUp(() {
    server.reset();
    ProSalonScope.clear();
  });

  Appointment appt({
    required String id,
    String time = '10:00',
    int day = 13,
    String status = 'pending',
    String providerId = 'p1',
    String? phone,
  }) => Appointment(
    id: id,
    userId: 'u-$id',
    providerId: providerId,
    serviceIds: const ['s1'],
    appointmentDate: DateTime.parse('2026-07-${day}T$time:00.000Z'),
    status: AppointmentStatus.values.byName(status),
    totalPrice: 10000,
    clientPhone: phone,
    createdAt: DateTime.utc(2026, 7, 1),
  );

  BookingChange change(
    String id,
    BookingChangeKind kind, {
    String providerId = 'p1',
    DateTime? newDate,
    DateTime? arrivedAt,
  }) => BookingChange(
    appointmentId: id,
    providerId: providerId,
    kind: kind,
    newDate: newDate,
    arrivedAt: arrivedAt,
  );

  group('ProSalonScope.bookingChanged — one announcement', () {
    test(
      'every store that hears booking changes is told; the others are not',
      () {
        final a = ProSalonScope.track(_Ear());
        final b = ProSalonScope.track(_Ear());
        ProSalonScope.track(_Deaf());
        ProSalonScope.bookingChanged(change('a1', BookingChangeKind.accepted));
        expect(a.heard.single.appointmentId, 'a1');
        expect(b.heard.single.kind, BookingChangeKind.accepted);
      },
    );

    test('the store that made the change is not told again (`except`)', () {
      final maker = ProSalonScope.track(_Ear());
      final other = ProSalonScope.track(_Ear());
      ProSalonScope.bookingChanged(
        change('a1', BookingChangeKind.completed),
        except: maker,
      );
      expect(maker.heard, isEmpty);
      expect(other.heard, hasLength(1));
    });

    test(
      'a store that throws is skipped — the next one still hears, nothing escapes',
      () {
        ProSalonScope.track(_Ear()..explode = true);
        final after = ProSalonScope.track(_Ear());
        expect(
          () => ProSalonScope.bookingChanged(
            change('a1', BookingChangeKind.noShow),
          ),
          returnsNormally,
        );
        expect(after.heard, hasLength(1));
      },
    );
  });

  group('« Ma journée » hears a change', () {
    Future<ProJournalProvider> openDay(List<Appointment> rows) async {
      server.bookings.addAll(rows);
      final p = ProJournalProvider();
      addTearDown(p.dispose);
      await p.load('p1', date: DateTime.utc(2026, 7, 13));
      return p;
    }

    Appointment row(ProJournalProvider p, String id) =>
        p.day!.appointments.firstWhere((a) => a.id == id);

    test(
      'accepted: the row says confirmed AT ONCE, before the reload answers',
      () async {
        final p = await openDay([appt(id: 'a1')]);
        final before = server.journalCalls;
        server.journalGate = Completer<void>();
        // The server already holds the new state (the write succeeded).
        server.bookings[0] = server.bookings[0].copyWith(
          status: AppointmentStatus.confirmed,
        );
        p.bookingChanged(change('a1', BookingChangeKind.accepted));
        expect(row(p, 'a1').status, AppointmentStatus.confirmed);
        expect(p.isLoading, isFalse, reason: 'no loader');
        expect(
          server.journalCalls,
          before + 1,
          reason: 'a quiet reload was asked',
        );
        server.journalGate!.complete();
        await pumpEventQueue();
        expect(row(p, 'a1').status, AppointmentStatus.confirmed);
      },
    );

    test(
      'rejected: cancelled, so hidden by default, and the day’s dot drops',
      () async {
        final p = await openDay([
          appt(id: 'a1'),
          appt(id: 'a2', time: '11:00'),
        ]);
        await pumpEventQueue();
        final key = p.keyOf(DateTime.utc(2026, 7, 13));
        expect(p.weekCounts[key], 2);
        server.journalGate = Completer<void>();
        p.bookingChanged(change('a1', BookingChangeKind.rejected));
        expect(row(p, 'a1').status, AppointmentStatus.cancelled);
        expect(p.visibleAppointments.map((a) => a.id), ['a2']);
        expect(p.weekCounts[key], 1);
      },
    );

    test(
      'completed, no-show, arrived: each lands on the row at once',
      () async {
        final p = await openDay([
          appt(id: 'c', status: 'confirmed'),
          appt(id: 'n', status: 'confirmed', time: '08:00'),
          appt(id: 'r', status: 'confirmed', time: '11:00'),
        ]);
        server.journalGate = Completer<void>();
        p.bookingChanged(change('c', BookingChangeKind.completed));
        p.bookingChanged(change('n', BookingChangeKind.noShow));
        final at = DateTime.utc(2026, 7, 13, 10, 58);
        p.bookingChanged(change('r', BookingChangeKind.arrived, arrivedAt: at));
        expect(row(p, 'c').status, AppointmentStatus.completed);
        expect(row(p, 'n').status, AppointmentStatus.noShow);
        expect(row(p, 'r').arrivedAt, at);
      },
    );

    test(
      'rescheduled to another day: it leaves this day and its dot moves',
      () async {
        final p = await openDay([appt(id: 'a1', status: 'confirmed')]);
        await pumpEventQueue();
        final today = p.keyOf(DateTime.utc(2026, 7, 13));
        final wednesday = p.keyOf(DateTime.utc(2026, 7, 15));
        server.journalGate = Completer<void>();
        p.bookingChanged(
          change(
            'a1',
            BookingChangeKind.rescheduled,
            newDate: DateTime.utc(2026, 7, 15, 14),
          ),
        );
        expect(p.day!.appointments.where((a) => a.id == 'a1'), isEmpty);
        expect(p.weekCounts[today] ?? 0, 0);
        expect(p.weekCounts[wednesday], 1);
      },
    );

    test(
      'the quiet reload fails: the updated row stays — no error, no loader',
      () async {
        final p = await openDay([appt(id: 'a1')]);
        server.journalFailure = 'throw';
        p.bookingChanged(change('a1', BookingChangeKind.accepted));
        await pumpEventQueue();
        expect(row(p, 'a1').status, AppointmentStatus.confirmed);
        expect(p.error, isNull);
        expect(p.isLoading, isFalse);
      },
    );

    test(
      'another salon’s booking: nothing changes, nothing is asked',
      () async {
        final p = await openDay([appt(id: 'a1')]);
        final before = server.journalCalls;
        p.bookingChanged(
          change('a1', BookingChangeKind.accepted, providerId: 'p2'),
        );
        expect(row(p, 'a1').status, AppointmentStatus.pending);
        expect(server.journalCalls, before);
      },
    );
  });

  group('« Ma journée »’s own gestures', () {
    Future<ProJournalProvider> trackedDay(List<Appointment> rows) async {
      server.bookings.addAll(rows);
      final p = ProSalonScope.track(ProJournalProvider());
      addTearDown(p.dispose);
      await p.load('p1', date: DateTime.utc(2026, 7, 13));
      return p;
    }

    test(
      'a gesture the server accepted, whose reload then FAILS, keeps the day — '
      'it used to drop it for « Une erreur est survenue »',
      () async {
        final p = await trackedDay([appt(id: 'a1')]);
        server.journalFailure = 'throw';
        expect(await p.accept('a1'), isTrue);
        await pumpEventQueue();
        expect(p.error, isNull);
        expect(p.day, isNotNull);
        expect(p.day!.appointments.single.status, AppointmentStatus.confirmed);
      },
    );

    test(
      'a gesture is announced to the other stores, after the server’s success',
      () async {
        final p = await trackedDay([
          appt(id: 'a1', status: 'confirmed', phone: '+2250700000001'),
        ]);
        final ear = ProSalonScope.track(_Ear());
        expect(await p.complete('a1'), isTrue);
        expect(ear.heard.single.kind, BookingChangeKind.completed);
        expect(ear.heard.single.appointmentId, 'a1');
        expect(ear.heard.single.providerId, 'p1');
        expect(ear.heard.single.clientPhone, '+2250700000001');
      },
    );

    test('a refused gesture announces nothing and says so', () async {
      final p = await trackedDay([appt(id: 'a1')]);
      final ear = ProSalonScope.track(_Ear());
      server.refuseWrites = true;
      expect(await p.accept('a1'), isFalse);
      expect(ear.heard, isEmpty);
      expect(p.error, isNotNull);
      expect(p.day!.appointments.single.status, AppointmentStatus.pending);
    });
  });

  group('the « Rendez-vous » list (ProAppointmentProvider)', () {
    Future<ProAppointmentProvider> loadedList(List<Appointment> rows) async {
      server.bookings.addAll(rows);
      final p = ProSalonScope.track(ProAppointmentProvider());
      addTearDown(p.dispose);
      await p.loadAppointments('p1');
      return p;
    }

    test('a change made elsewhere corrects its row — no reload', () async {
      final p = await loadedList([appt(id: 'a1')]);
      final calls = server.listCalls;
      p.bookingChanged(change('a1', BookingChangeKind.accepted));
      expect(p.appointments.single.status, AppointmentStatus.confirmed);
      expect(server.listCalls, calls);
    });

    test(
      'its own four writes are announced to the others, once, after success',
      () async {
        final p = await loadedList([
          appt(id: 'a', status: 'pending'),
          appt(id: 'r', status: 'pending', time: '11:00'),
          appt(id: 'c', status: 'confirmed', time: '08:00'),
          appt(id: 'n', status: 'confirmed', time: '07:00'),
        ]);
        final ear = ProSalonScope.track(_Ear());
        expect(await p.acceptAppointment('a'), isTrue);
        expect(await p.rejectAppointment('r', null), isTrue);
        expect(await p.markComplete('c'), isTrue);
        expect(await p.markNoShow('n'), isTrue);
        expect(ear.heard.map((c) => (c.appointmentId, c.kind)), [
          ('a', BookingChangeKind.accepted),
          ('r', BookingChangeKind.rejected),
          ('c', BookingChangeKind.completed),
          ('n', BookingChangeKind.noShow),
        ]);
      },
    );

    test('a refused write announces nothing', () async {
      final p = await loadedList([appt(id: 'a')]);
      final ear = ProSalonScope.track(_Ear());
      server.refuseWrites = true;
      expect(await p.acceptAppointment('a'), isFalse);
      expect(ear.heard, isEmpty);
    });
  });
}
