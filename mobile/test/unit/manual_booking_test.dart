import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';

class _MockProService extends Mock implements ProServiceInterface {}

void main() {
  test('Appointment round-trips the walk-in client fields', () {
    final a = Appointment(
      id: 'm1',
      userId: 'manual',
      providerId: 'p1',
      serviceIds: const ['s1'],
      appointmentDate: DateTime(2026, 7, 1, 10),
      status: AppointmentStatus.confirmed,
      totalPrice: 15000,
      clientName: 'Awa',
      clientPhone: '+2250700000012',
      createdAt: DateTime(2026),
    );
    final back = Appointment.fromJson(a.toJson());
    expect(back.clientName, 'Awa');
    expect(back.clientPhone, '+2250700000012');
    expect(back.status, AppointmentStatus.confirmed);
  });

  group('ProAppointmentProvider.createManualBooking', () {
    late _MockProService service;

    setUpAll(() {
      service = _MockProService();
      serviceLocator.proService = service;
      registerFallbackValue(<String>[]);
      registerFallbackValue(DateTime(2024));
    });

    setUp(() => reset(service));

    Appointment created() => Appointment(
      id: 'm1',
      userId: 'manual',
      providerId: 'p1',
      serviceIds: const ['s1'],
      appointmentDate: DateTime(2026, 7, 1, 10),
      status: AppointmentStatus.confirmed,
      totalPrice: 15000,
      clientPhone: '+2250700000012',
      createdAt: DateTime(2026),
    );

    void stub(ApiResponse<Appointment> response) {
      when(
        () => service.createManualBooking(
          providerId: any(named: 'providerId'),
          serviceIds: any(named: 'serviceIds'),
          appointmentDateTime: any(named: 'appointmentDateTime'),
          clientName: any(named: 'clientName'),
          clientPhone: any(named: 'clientPhone'),
          notes: any(named: 'notes'),
          sendSmsInvite: any(named: 'sendSmsInvite'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => response);
    }

    test('adds the created confirmed booking on success', () async {
      stub(ApiResponse.success(created()));

      final p = ProAppointmentProvider();
      final ok = await p.createManualBooking(
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDateTime: DateTime(2026, 7, 1, 10),
        clientPhone: '+2250700000012',
      );

      expect(ok, isTrue);
      expect(p.appointments.single.clientPhone, '+2250700000012');
      expect(p.appointments.single.status, AppointmentStatus.confirmed);
    });

    test('returns false and surfaces the error on failure', () async {
      stub(ApiResponse.error('boom'));

      final p = ProAppointmentProvider();
      final ok = await p.createManualBooking(
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDateTime: DateTime(2026, 7, 1, 10),
      );

      expect(ok, isFalse);
      expect(p.error, 'boom');
    });
  });

  /// docs/design/pro-journal-shows-new-booking.md §2.6 — « Rendez-vous »
  /// keeps one list and reloads it per tab. The created booking used to be
  /// appended whatever the list had been loaded with.
  group('a created booking joins the agenda only where it belongs', () {
    late _MockProService service;

    setUpAll(() {
      // `serviceLocator.proService` is late final: the group above owns the
      // assignment, and this is the same mock.
      service = serviceLocator.proService as _MockProService;
    });

    setUp(() => reset(service));

    // A confirmed booking on 1 July 2026 at 10:00 (UTC).
    final at = DateTime.utc(2026, 7, 1, 10);
    Appointment created() => Appointment(
      id: 'm1',
      userId: 'manual',
      providerId: 'p1',
      serviceIds: const ['s1'],
      appointmentDate: at,
      status: AppointmentStatus.confirmed,
      totalPrice: 15000,
      createdAt: DateTime.utc(2026),
    );

    /// Loads the agenda the way one of its tabs does, then creates.
    Future<ProAppointmentProvider> loadedThenCreated({
      AppointmentStatus? status,
      DateTime? from,
      DateTime? to,
    }) async {
      when(
        () => service.getProviderAppointments(
          any(),
          status: any(named: 'status'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => ApiResponse.success(<Appointment>[]));
      when(
        () => service.createManualBooking(
          providerId: any(named: 'providerId'),
          serviceIds: any(named: 'serviceIds'),
          appointmentDateTime: any(named: 'appointmentDateTime'),
          clientName: any(named: 'clientName'),
          clientPhone: any(named: 'clientPhone'),
          notes: any(named: 'notes'),
          artistId: any(named: 'artistId'),
          sendSmsInvite: any(named: 'sendSmsInvite'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => ApiResponse.success(created()));

      final p = ProAppointmentProvider();
      await p.loadAppointments(
        'p1',
        status: status,
        startDate: from,
        endDate: to,
      );
      final ok = await p.createManualBooking(
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDateTime: at,
      );
      expect(ok, isTrue, reason: 'the booking is created either way');
      return p;
    }

    test('« Calendrier » / « Tous » (no filter): it joins', () async {
      final p = await loadedThenCreated();
      expect(p.appointments.single.id, 'm1');
    });

    test('« En attente »: a « Confirmé » booking does NOT join', () async {
      final p = await loadedThenCreated(status: AppointmentStatus.pending);
      expect(p.appointments, isEmpty);
    });

    test('« Aujourd’hui »: it joins on its day, not on another', () async {
      final sameDay = await loadedThenCreated(
        from: DateTime.utc(2026, 7, 1),
        to: DateTime.utc(2026, 7, 2),
      );
      expect(sameDay.appointments.single.id, 'm1');

      final dayBefore = await loadedThenCreated(
        from: DateTime.utc(2026, 6, 30),
        to: DateTime.utc(2026, 7, 1),
      );
      expect(dayBefore.appointments, isEmpty);

      final dayAfter = await loadedThenCreated(
        from: DateTime.utc(2026, 7, 2),
        to: DateTime.utc(2026, 7, 3),
      );
      expect(dayAfter.appointments, isEmpty);
    });

    test('« À venir » (from now on): it joins when it is ahead', () async {
      final ahead = await loadedThenCreated(from: DateTime.utc(2026, 6, 30));
      expect(ahead.appointments.single.id, 'm1');
      final behind = await loadedThenCreated(from: DateTime.utc(2026, 7, 2));
      expect(behind.appointments, isEmpty);
    });

    test('the bounds are inclusive, like the list’s own query', () async {
      final atStart = await loadedThenCreated(from: at, to: at);
      expect(atStart.appointments.single.id, 'm1');
    });

    // Each of the three is forgotten on its own: a list loaded with one of
    // them only, each of which keeps the booking out (asserted first).
    for (final (name, status, from, to)
        in <(String, AppointmentStatus?, DateTime?, DateTime?)>[
          ('the status', AppointmentStatus.pending, null, null),
          ('the start date', null, DateTime.utc(2026, 7, 2), null),
          ('the end date', null, null, DateTime.utc(2026, 6, 30)),
        ]) {
      test('a salon switch forgets the filter — $name', () async {
        final p = await loadedThenCreated(status: status, from: from, to: to);
        expect(p.appointments, isEmpty, reason: 'the filter keeps it out');

        p.resetForSalonSwitch();
        await p.createManualBooking(
          providerId: 'p1',
          serviceIds: const ['s1'],
          appointmentDateTime: at,
        );
        expect(p.appointments.single.id, 'm1');
      });
    }
  });
}
