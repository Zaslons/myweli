import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/client_booking_rule.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';

class _MockProService extends Mock implements ProServiceInterface {}

void main() {
  final now = DateTime(2026, 6, 22, 12);

  Appointment appt({
    String id = 'a1',
    AppointmentStatus status = AppointmentStatus.confirmed,
    DateTime? date,
  }) => Appointment(
    id: id,
    userId: 'u1',
    providerId: SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: date ?? DateTime(2026, 6, 1),
    status: status,
    totalPrice: 20000,
    createdAt: DateTime(2026),
  );

  test(
    'a no-show is listed in « Passés » as « Absent », never « Terminé »',
    () {
      // It used to be in no tab at all (consumer-app-truth.md §2.7).
      final absent = appt(
        id: 'absent',
        date: DateTime(2026, 6, 2),
        status: AppointmentStatus.noShow,
      );
      expect(clientTab(absent, now), ClientBookingTab.past);
      expect(clientStatusLabel(absent, now), 'Absent');
    },
  );

  group('ProAppointmentProvider.markNoShow', () {
    late _MockProService service;

    setUpAll(() {
      service = _MockProService();
      serviceLocator.proService = service;
    });

    setUp(() {
      reset(service);
      when(
        () => service.getProviderAppointments(
          any(),
          status: any(named: 'status'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => ApiResponse.success([appt()]));
    });

    test('marks the appointment as no-show on success', () async {
      when(
        () => service.markNoShow(any()),
      ).thenAnswer((_) async => ApiResponse.success(true));

      final p = ProAppointmentProvider();
      await p.loadAppointments(SalonId('p1'));
      final ok = await p.markNoShow('a1');

      expect(ok, isTrue);
      expect(p.appointments.single.status, AppointmentStatus.noShow);
    });

    test('returns false and surfaces the error on failure', () async {
      when(
        () => service.markNoShow(any()),
      ).thenAnswer((_) async => ApiResponse.error('boom'));

      final p = ProAppointmentProvider();
      await p.loadAppointments(SalonId('p1'));

      expect(await p.markNoShow('a1'), isFalse);
      expect(p.error, 'boom');
    });
  });
}
