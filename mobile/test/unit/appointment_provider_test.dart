import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';

class _MockAppointmentService extends Mock
    implements AppointmentServiceInterface {}

void main() {
  late _MockAppointmentService appointments;

  setUpAll(() {
    appointments = _MockAppointmentService();
    serviceLocator.appointmentService = appointments;
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime(2024));
  });

  setUp(() => reset(appointments));

  Appointment confirmed() => Appointment(
    id: 'a1',
    userId: 'u1',
    providerId: 'p1',
    serviceIds: const ['s1'],
    appointmentDate: DateTime(2024, 6, 24, 10),
    status: AppointmentStatus.confirmed,
    totalPrice: 20000,
    depositAmount: 6000,
    balanceDue: 14000,
    createdAt: DateTime(2024),
  );

  group('getAvailableTimeSlots distinguishes "closed" from "broken"', () {
    // **The block that renders this had three states, not four.** The provider
    // swallowed every failure into `return []`, so « Aucun créneau disponible »
    // was the sentence for a fully-booked Saturday AND for a dead network. On a
    // screen someone opens to move an appointment, that is the wrong sentence:
    // it says "the salon has no room" when the truth is "we could not ask".
    //
    // The layer below already knows — `ApiResponse` carries `error` and `code`.
    // Only the provider was throwing it away.

    test('a failure surfaces the error instead of an empty day', () async {
      when(
        () => appointments.getAvailableTimeSlots(
          providerId: any(named: 'providerId'),
          date: any(named: 'date'),
          serviceIds: any(named: 'serviceIds'),
          artistId: any(named: 'artistId'),
          durationMinutes: any(named: 'durationMinutes'),
        ),
      ).thenAnswer(
        (_) async => ApiResponse<List<DateTime>>.error('Hors ligne'),
      );

      final res = await AppointmentProvider().getAvailableTimeSlots(
        providerId: 'p1',
        date: DateTime(2026, 3, 11),
      );

      expect(res.slots, isEmpty);
      expect(
        res.error,
        'Hors ligne',
        reason:
            'without this the caller cannot tell a closed salon from a failed '
            'request, and both render the same reassuring lie',
      );
    });

    test('a real empty day is empty WITHOUT an error', () async {
      when(
        () => appointments.getAvailableTimeSlots(
          providerId: any(named: 'providerId'),
          date: any(named: 'date'),
          serviceIds: any(named: 'serviceIds'),
          artistId: any(named: 'artistId'),
          durationMinutes: any(named: 'durationMinutes'),
        ),
      ).thenAnswer((_) async => ApiResponse<List<DateTime>>.success(const []));

      final res = await AppointmentProvider().getAvailableTimeSlots(
        providerId: 'p1',
        date: DateTime(2026, 3, 11),
      );

      expect(res.slots, isEmpty);
      expect(
        res.error,
        isNull,
        reason:
            'the other direction: a genuinely full day must NOT be reported as '
            'an error, or the fix trades one wrong sentence for another',
      );
    });
  });

  test(
    'bookAppointment stores the returned booking + threads the deposit',
    () async {
      when(
        () => appointments.bookAppointment(
          providerId: any(named: 'providerId'),
          serviceIds: any(named: 'serviceIds'),
          appointmentDateTime: any(named: 'appointmentDateTime'),
          artistId: any(named: 'artistId'),
          notes: any(named: 'notes'),
          depositAmount: any(named: 'depositAmount'),
          depositScreenshotUrl: any(named: 'depositScreenshotUrl'),
        ),
      ).thenAnswer((_) async => ApiResponse.success(confirmed()));

      final provider = AppointmentProvider();
      final ok = await provider.bookAppointment(
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDateTime: DateTime(2024, 6, 24, 10),
        depositAmount: 6000,
        depositScreenshotUrl: 'asset:proof.png',
      );

      expect(ok, isTrue);
      expect(provider.appointments, hasLength(1));
      verify(
        () => appointments.bookAppointment(
          providerId: 'p1',
          serviceIds: const ['s1'],
          appointmentDateTime: DateTime(2024, 6, 24, 10),
          artistId: null,
          notes: null,
          depositAmount: 6000,
          depositScreenshotUrl: 'asset:proof.png',
        ),
      ).called(1);
    },
  );

  test(
    'rescheduleAppointment moves the stored appointment on success',
    () async {
      when(
        () => appointments.getUserAppointments(status: any(named: 'status')),
      ).thenAnswer((_) async => ApiResponse.success([confirmed()]));
      final newDate = DateTime(2024, 6, 25, 14);
      when(
        () => appointments.rescheduleAppointment(
          id: any(named: 'id'),
          newDateTime: any(named: 'newDateTime'),
        ),
      ).thenAnswer(
        (_) async =>
            ApiResponse.success(confirmed().copyWith(appointmentDate: newDate)),
      );

      final provider = AppointmentProvider();
      await provider.loadAppointments();
      final ok = await provider.rescheduleAppointment(
        id: 'a1',
        newDateTime: newDate,
      );

      expect(ok, isTrue);
      expect(provider.appointments.single.appointmentDate, newDate);
    },
  );

  test(
    'rescheduleAppointment keeps the date and surfaces the error on failure',
    () async {
      when(
        () => appointments.getUserAppointments(status: any(named: 'status')),
      ).thenAnswer((_) async => ApiResponse.success([confirmed()]));
      when(
        () => appointments.rescheduleAppointment(
          id: any(named: 'id'),
          newDateTime: any(named: 'newDateTime'),
        ),
      ).thenAnswer((_) async => ApiResponse.error('boom'));

      final provider = AppointmentProvider();
      await provider.loadAppointments();
      final ok = await provider.rescheduleAppointment(
        id: 'a1',
        newDateTime: DateTime(2024, 6, 25, 14),
      );

      expect(ok, isFalse);
      expect(
        provider.appointments.single.appointmentDate,
        DateTime(2024, 6, 24, 10),
      );
      expect(provider.error, 'boom');
    },
  );

  test(
    'visitHistory exposes past, non-cancelled appointments as visits',
    () async {
      final past = confirmed(); // 2024 → elapsed
      final cancelled = confirmed().copyWith(
        id: 'a2',
        status: AppointmentStatus.cancelled,
      );
      final future = confirmed().copyWith(
        id: 'a3',
        appointmentDate: DateTime.now().add(const Duration(days: 7)),
      );
      when(
        () => appointments.getUserAppointments(status: any(named: 'status')),
      ).thenAnswer((_) async => ApiResponse.success([past, cancelled, future]));

      final provider = AppointmentProvider();
      await provider.loadAppointments();

      expect(provider.visitHistory.map((a) => a.id), ['a1']);
    },
  );

  test(
    'submitDeposit refreshes the stored appointment with the screenshot',
    () async {
      final pending = confirmed().copyWith(status: AppointmentStatus.pending);
      when(
        () => appointments.getUserAppointments(status: any(named: 'status')),
      ).thenAnswer((_) async => ApiResponse.success([pending]));
      when(
        () => appointments.submitDeposit(
          appointmentId: any(named: 'appointmentId'),
          screenshotKey: any(named: 'screenshotKey'),
        ),
      ).thenAnswer(
        (_) async => ApiResponse.success(
          pending.copyWith(depositScreenshotUrl: 'deposit/u1/x.jpg'),
        ),
      );

      final provider = AppointmentProvider();
      await provider.loadAppointments();
      final ok = await provider.submitDeposit(
        appointmentId: 'a1',
        screenshotKey: 'deposit/u1/x.jpg',
      );

      expect(ok, isTrue);
      expect(
        provider.appointments.single.depositScreenshotUrl,
        'deposit/u1/x.jpg',
      );
    },
  );
}
