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
      when(() => service.createManualBooking(
            providerId: any(named: 'providerId'),
            serviceIds: any(named: 'serviceIds'),
            appointmentDateTime: any(named: 'appointmentDateTime'),
            clientName: any(named: 'clientName'),
            clientPhone: any(named: 'clientPhone'),
            notes: any(named: 'notes'),
            sendSmsInvite: any(named: 'sendSmsInvite'),
          )).thenAnswer((_) async => response);
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
}
