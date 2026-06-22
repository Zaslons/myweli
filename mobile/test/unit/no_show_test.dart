import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/visit_history.dart';
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
  }) =>
      Appointment(
        id: id,
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: date ?? DateTime(2026, 6, 1),
        status: status,
        totalPrice: 20000,
        createdAt: DateTime(2026),
      );

  test('a no-show stays no-show and is excluded from visit history', () {
    final list = [
      appt(id: 'done', date: DateTime(2026, 6, 1)),
      appt(
          id: 'absent',
          date: DateTime(2026, 6, 2),
          status: AppointmentStatus.noShow),
    ];
    expect(effectiveAppointmentStatus(list[1], now), AppointmentStatus.noShow);
    expect(visitHistory(list, now).map((a) => a.id), ['done']);
  });

  group('ProAppointmentProvider.markNoShow', () {
    late _MockProService service;

    setUpAll(() {
      service = _MockProService();
      serviceLocator.proService = service;
    });

    setUp(() {
      reset(service);
      when(() => service.getProviderAppointments(
            any(),
            status: any(named: 'status'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          )).thenAnswer((_) async => ApiResponse.success([appt()]));
    });

    test('marks the appointment as no-show on success', () async {
      when(() => service.markNoShow(any()))
          .thenAnswer((_) async => ApiResponse.success(true));

      final p = ProAppointmentProvider();
      await p.loadAppointments('p1');
      final ok = await p.markNoShow('a1');

      expect(ok, isTrue);
      expect(p.appointments.single.status, AppointmentStatus.noShow);
    });

    test('returns false and surfaces the error on failure', () async {
      when(() => service.markNoShow(any()))
          .thenAnswer((_) async => ApiResponse.error('boom'));

      final p = ProAppointmentProvider();
      await p.loadAppointments('p1');

      expect(await p.markNoShow('a1'), isFalse);
      expect(p.error, 'boom');
    });
  });
}
