import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// « A booking was created » has ONE owner
/// (docs/design/pro-journal-shows-new-booking.md §5): the announcement
/// `ProSalonScope.bookingCreated`, made by
/// `ProAppointmentProvider.createManualBooking` and heard by every tracked
/// store that shows bookings.
class _Service extends MockProService {
  /// 'ok', 'refused' or 'throw'.
  String outcome = 'ok';
  int calls = 0;

  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async => ApiResponse.success(<Appointment>[]);

  @override
  Future<ApiResponse<Appointment>> createManualBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? clientName,
    String? clientPhone,
    String? notes,
    String? artistId,
    bool sendSmsInvite = false,
  }) async {
    calls++;
    if (outcome == 'throw') throw Exception('SocketException');
    if (outcome == 'refused') {
      return ApiResponse.error(
        'Ce créneau n’est plus disponible.',
        code: 'slot_unavailable',
      );
    }
    return ApiResponse.success(
      Appointment(
        id: 'm$calls',
        userId: 'manual',
        providerId: providerId,
        serviceIds: serviceIds,
        artistId: artistId,
        appointmentDate: appointmentDateTime,
        status: AppointmentStatus.confirmed,
        totalPrice: 5000,
        durationMinutes: 30,
        clientName: clientName,
        clientPhone: clientPhone,
        createdAt: DateTime.utc(2026, 7, 1),
      ),
    );
  }
}

/// A store that shows bookings.
class _Shows implements ShowsSalonBookings {
  final heard = <Appointment>[];
  int resets = 0;

  @override
  void bookingCreated(Appointment booking) => heard.add(booking);

  // Changes are another announcement (pro_booking_changed_test.dart).
  @override
  void bookingChanged(BookingChange change) {}

  @override
  void resetForSalonSwitch() => resets++;
}

/// A store that shows bookings and has a bug.
class _Throws implements ShowsSalonBookings {
  int calls = 0;

  @override
  void bookingCreated(Appointment booking) {
    calls++;
    throw StateError('a store with a bug');
  }

  // Changes are another announcement (pro_booking_changed_test.dart).
  @override
  void bookingChanged(BookingChange change) {}

  @override
  void resetForSalonSwitch() {}
}

/// A store that shows bookings and, on hearing of one, brings another store
/// to life — which registers itself, as every per-salon store does.
class _Spawns implements ShowsSalonBookings {
  final spawned = <_Shows>[];

  @override
  void bookingCreated(Appointment booking) =>
      spawned.add(ProSalonScope.track(_Shows()));

  // Changes are another announcement (pro_booking_changed_test.dart).
  @override
  void bookingChanged(BookingChange change) {}

  @override
  void resetForSalonSwitch() {}
}

/// A per-salon store that shows no booking (services, photos…).
class _Other implements SalonScoped {
  int resets = 0;

  @override
  void resetForSalonSwitch() => resets++;
}

void main() {
  final service = _Service();

  setUpAll(() {
    serviceLocator.proService = service; // late final — one fake for the file
  });

  setUp(() {
    ProSalonScope.clear();
    service
      ..outcome = 'ok'
      ..calls = 0;
  });

  final booking = Appointment(
    id: 'm1',
    userId: 'manual',
    providerId: 'p1',
    serviceIds: const ['s1'],
    appointmentDate: DateTime.utc(2026, 7, 13, 10),
    status: AppointmentStatus.confirmed,
    totalPrice: 5000,
    createdAt: DateTime.utc(2026, 7, 1),
  );

  Future<bool> create(ProAppointmentProvider p) => p.createManualBooking(
    providerId: 'p1',
    serviceIds: const ['s1'],
    appointmentDateTime: DateTime.utc(2026, 7, 13, 10),
    clientName: 'Yao K.',
  );

  group('ProSalonScope.bookingCreated', () {
    test('every tracked store that shows bookings hears it, once', () {
      final a = ProSalonScope.track(_Shows());
      final b = ProSalonScope.track(_Shows());
      final other = ProSalonScope.track(_Other());

      ProSalonScope.bookingCreated(booking);

      expect(a.heard, [booking]);
      expect(b.heard, [booking]);
      expect(other.resets, 0, reason: 'an announcement is not a reset');
      expect(a.resets, 0);
    });

    test('a store that is not tracked hears nothing', () {
      final untracked = _Shows();
      ProSalonScope.bookingCreated(booking);
      expect(untracked.heard, isEmpty);
    });

    test('a store that throws is skipped: the others are still told, and '
        'nothing escapes', () {
      final before = ProSalonScope.track(_Shows());
      final broken = ProSalonScope.track(_Throws());
      final after = ProSalonScope.track(_Shows());

      expect(() => ProSalonScope.bookingCreated(booking), returnsNormally);

      expect(broken.calls, 1);
      expect(before.heard, [booking]);
      expect(after.heard, [booking], reason: 'the store AFTER the broken one');
    });

    test('a store that registers ANOTHER store while being told does not '
        'break the round: nothing escapes, the stores after it are told', () {
      // The registry is a growable list, and growing a list while it is being
      // walked throws — from the loop itself, outside any store's `try`. It
      // would reach `createManualBooking` as a failed creation of a booking
      // that exists.
      final before = ProSalonScope.track(_Shows());
      final spawner = ProSalonScope.track(_Spawns());
      final after = ProSalonScope.track(_Shows());

      expect(() => ProSalonScope.bookingCreated(booking), returnsNormally);

      expect(before.heard, [booking]);
      expect(spawner.spawned, hasLength(1));
      expect(after.heard, [booking], reason: 'the store AFTER the spawner');
      expect(
        spawner.spawned.single.heard,
        isEmpty,
        reason: 'born after the announcement began: it reads the server',
      );
    });

    test('a salon switch still resets every tracked store', () {
      final shows = ProSalonScope.track(_Shows());
      final other = ProSalonScope.track(_Other());
      ProSalonScope.resetAll();
      expect(shows.resets, 1);
      expect(other.resets, 1);
      expect(shows.heard, isEmpty);
    });
  });

  group('ProAppointmentProvider.createManualBooking announces', () {
    test('a created booking: once, with the server’s own answer', () async {
      final store = ProSalonScope.track(_Shows());
      final p = ProSalonScope.track(ProAppointmentProvider());

      expect(await create(p), isTrue);

      expect(store.heard, hasLength(1));
      expect(store.heard.single.id, 'm1');
      expect(store.heard.single.status, AppointmentStatus.confirmed);
      expect(store.heard.single.clientName, 'Yao K.');
      expect(store.heard.single, same(p.appointments.single));
    });

    test('BEFORE it returns — the form closes on a day that is already '
        'right', () async {
      final store = ProSalonScope.track(_Shows());
      final p = ProAppointmentProvider();
      var heardWhenDone = -1;
      await create(p).then((_) => heardWhenDone = store.heard.length);
      expect(heardWhenDone, 1);
    });

    test('a booking the agenda’s own list does not take is announced all '
        'the same — « Ma journée » does not depend on which tab the agenda '
        'was left on', () async {
      final store = ProSalonScope.track(_Shows());
      final p = ProAppointmentProvider();
      // The agenda was left on « En attente »; the booking is « Confirmé ».
      await p.loadAppointments('p1', status: AppointmentStatus.pending);

      expect(await create(p), isTrue);

      expect(p.appointments, isEmpty, reason: 'not under « En attente »');
      expect(store.heard.single.id, 'm1');
    });

    test('a refused creation announces nothing', () async {
      final store = ProSalonScope.track(_Shows());
      final p = ProAppointmentProvider();
      service.outcome = 'refused';

      expect(await create(p), isFalse);

      expect(store.heard, isEmpty);
      expect(p.error, 'Ce créneau n’est plus disponible.');
      expect(p.errorCode, 'slot_unavailable');
      expect(p.appointments, isEmpty);
    });

    test('a creation that never got an answer announces nothing', () async {
      final store = ProSalonScope.track(_Shows());
      final p = ProAppointmentProvider();
      service.outcome = 'throw';

      expect(await create(p), isFalse);
      expect(store.heard, isEmpty);
    });

    test('a store that throws does NOT turn a created booking into a failed '
        'creation — the salon would create it twice', () async {
      ProSalonScope.track(_Throws());
      final store = ProSalonScope.track(_Shows());
      final p = ProAppointmentProvider();

      expect(await create(p), isTrue);

      expect(p.error, isNull);
      expect(p.appointments.single.id, 'm1');
      expect(store.heard, hasLength(1));
      expect(service.calls, 1);
    });
  });

  group('the wiring is the app’s own (main_pro.dart)', () {
    /// Source with its `//` comments removed: a sentence ABOUT the wiring must
    /// not be able to stand in for the wiring.
    String code(String path) => File(path)
        .readAsLinesSync()
        .map((line) {
          final at = line.indexOf('//');
          return at < 0 ? line : line.substring(0, at);
        })
        .join('\n');

    final mainPro = code('lib/main_pro.dart');

    /// Every provider whose class header names `ShowsSalonBookings`, however
    /// the header is written (`implements A, B`, a mixin in between…).
    final stores = [
      for (final f in Directory('lib/providers').listSync().whereType<File>())
        for (final m in RegExp(
          r'class\s+(\w+)\b[^{;]*\bShowsSalonBookings\b[^{;]*\{',
        ).allMatches(code(f.path)))
          m.group(1)!,
    ]..sort();

    test('the stores that show bookings are the three the spec names', () {
      expect(stores, [
        'ProClientsProvider',
        'ProDashboardProvider',
        'ProJournalProvider',
      ]);
    });

    test('each one is registered with ProSalonScope.track — an untracked '
        'store is never told', () {
      for (final store in stores) {
        expect(
          'ProSalonScope.track($store())'.allMatches(mainPro),
          hasLength(1),
          reason: '$store is not tracked in main_pro.dart',
        );
      }
    });

    test('the announcer is tracked too, and there is one announcement in '
        'the app', () {
      // Not needed to announce — it is what makes this file's harness the
      // app's own, and the day it is un-tracked a salon switch stops
      // resetting the agenda.
      expect(
        'ProSalonScope.track(ProAppointmentProvider())'.allMatches(mainPro),
        hasLength(1),
      );
      final callers = [
        for (final f in Directory(
          'lib',
        ).listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              !f.path.endsWith('pro_salon_scope.dart') &&
              code(f.path).contains('ProSalonScope.bookingCreated('))
            f.path,
      ];
      expect(callers, ['lib/providers/pro_appointment_provider.dart']);
    });
  });
}
