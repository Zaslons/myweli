import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/interfaces/payment_service_interface.dart';

class _MockAppointmentService extends Mock
    implements AppointmentServiceInterface {}

class _MockPaymentService extends Mock implements PaymentServiceInterface {}

void main() {
  late _MockAppointmentService appointments;
  late _MockPaymentService payments;

  setUpAll(() {
    appointments = _MockAppointmentService();
    payments = _MockPaymentService();
    serviceLocator.appointmentService = appointments;
    serviceLocator.paymentService = payments;
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime(2024));
    registerFallbackValue(MobileMoneyOperator.wave);
  });

  setUp(() {
    reset(appointments);
    reset(payments);
  });

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

  test('payDepositAndBook books after a successful deposit', () async {
    when(
      () => payments.payDeposit(
        amount: any(named: 'amount'),
        operator: any(named: 'operator'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.success(
        const PaymentResult(success: true, reference: 'R1'),
      ),
    );
    when(
      () => appointments.bookAppointment(
        providerId: any(named: 'providerId'),
        serviceIds: any(named: 'serviceIds'),
        appointmentDateTime: any(named: 'appointmentDateTime'),
        artistId: any(named: 'artistId'),
        notes: any(named: 'notes'),
        depositAmount: any(named: 'depositAmount'),
      ),
    ).thenAnswer((_) async => ApiResponse.success(confirmed()));

    final provider = AppointmentProvider();
    final ok = await provider.payDepositAndBook(
      providerId: 'p1',
      serviceIds: const ['s1'],
      appointmentDateTime: DateTime(2024, 6, 24, 10),
      depositAmount: 6000,
      operator: MobileMoneyOperator.wave,
    );

    expect(ok, isTrue);
    expect(provider.appointments, hasLength(1));
    verify(
      () => payments.payDeposit(
        amount: 6000,
        operator: MobileMoneyOperator.wave,
      ),
    ).called(1);
  });

  test('payDepositAndBook does not book when the deposit fails', () async {
    when(
      () => payments.payDeposit(
        amount: any(named: 'amount'),
        operator: any(named: 'operator'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.success(
        const PaymentResult(success: false, error: 'Paiement refusé'),
      ),
    );

    final provider = AppointmentProvider();
    final ok = await provider.payDepositAndBook(
      providerId: 'p1',
      serviceIds: const ['s1'],
      appointmentDateTime: DateTime(2024, 6, 24, 10),
      depositAmount: 6000,
      operator: MobileMoneyOperator.wave,
    );

    expect(ok, isFalse);
    expect(provider.appointments, isEmpty);
    expect(provider.error, isNotNull);
  });

  test('rescheduleAppointment moves the stored appointment on success',
      () async {
    when(() => appointments.getUserAppointments(status: any(named: 'status')))
        .thenAnswer((_) async => ApiResponse.success([confirmed()]));
    final newDate = DateTime(2024, 6, 25, 14);
    when(
      () => appointments.rescheduleAppointment(
        id: any(named: 'id'),
        newDateTime: any(named: 'newDateTime'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.success(
        confirmed().copyWith(appointmentDate: newDate),
      ),
    );

    final provider = AppointmentProvider();
    await provider.loadAppointments();
    final ok =
        await provider.rescheduleAppointment(id: 'a1', newDateTime: newDate);

    expect(ok, isTrue);
    expect(provider.appointments.single.appointmentDate, newDate);
  });

  test('rescheduleAppointment keeps the date and surfaces the error on failure',
      () async {
    when(() => appointments.getUserAppointments(status: any(named: 'status')))
        .thenAnswer((_) async => ApiResponse.success([confirmed()]));
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
    expect(provider.appointments.single.appointmentDate,
        DateTime(2024, 6, 24, 10));
    expect(provider.error, 'boom');
  });
}
