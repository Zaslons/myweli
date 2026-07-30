import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthService extends Mock implements AuthServiceInterface {}

void main() {
  group('MockAuthService.deleteAccount', () {
    const phone = '+2250700000088';

    test('clears the session after a logged-in delete', () async {
      final service = MockAuthService();
      await service.sendOtp(phone);
      await service.verifyOtp(phone, '123456');

      final res = await service.deleteAccount();
      expect(res.success, isTrue);
      expect(await service.getCurrentUser(), isNull);
    });

    test('fails when no user is signed in', () async {
      final service = MockAuthService();
      final res = await service.deleteAccount();
      expect(res.success, isFalse);
    });
  });

  group('AuthProvider.deleteAccount', () {
    late _MockAuthService service;

    setUpAll(() {
      service = _MockAuthService();
      serviceLocator.authService = service;
    });

    setUp(() {
      reset(service);
      when(() => service.getCurrentUser()).thenAnswer((_) async => null);
    });

    test('returns true and clears the user on success', () async {
      when(
        () => service.deleteAccount(),
      ).thenAnswer((_) async => ApiResponse.success(null));

      final provider = AuthProvider();
      final ok = await provider.deleteAccount();

      expect(ok, isTrue);
      expect(provider.user, isNull);
      expect(provider.isAuthenticated, isFalse);
    });

    test('returns false and surfaces the error on failure', () async {
      when(
        () => service.deleteAccount(),
      ).thenAnswer((_) async => ApiResponse.error('boom'));

      final provider = AuthProvider();
      final ok = await provider.deleteAccount();

      expect(ok, isFalse);
      expect(provider.error, 'boom');
    });
  });

  group('L2 — settle the agenda first', () {
    test('a confirmed booking ahead refuses the deletion', () async {
      // Owner decision, mirroring the provider path: a salon holds a slot for a
      // named person, and an account that vanishes without cancelling leaves a
      // booking it can neither contact nor fill. The MOCK must refuse the same
      // way the API does, or the app behaves differently off-network — and the
      // guardrails ask mocks to simulate errors, not only happy paths.
      SharedPreferences.setMockInitialValues({});
      final service = MockAuthService();
      MockData.resetAppointments();

      const phone = '+2250700000077';
      await service.sendOtp(phone);
      await service.verifyOtp(phone, '123456');
      final me = await service.getCurrentUser();
      expect(me, isNotNull);

      MockData.appointments.add(
        Appointment(
          id: 'appt-future',
          userId: me!.id,
          providerId: 'provider1',
          serviceIds: const ['s1'],
          appointmentDate: AppClock.now().add(const Duration(days: 1)),
          status: AppointmentStatus.confirmed,
          totalPrice: 5000,
          createdAt: AppClock.now(),
        ),
      );

      final res = await service.deleteAccount();
      expect(res.success, isFalse);
      expect(res.code, 'future_bookings');
      expect(
        res.error,
        contains('Annulez'),
        reason:
            'the user must be told WHAT to do — a bare « échec » leaves '
            'them with an account they cannot close and no idea why',
      );
      expect(
        MockData.users.any((u) => u.id == me.id),
        isTrue,
        reason: 'and the refusal erased nothing',
      );
    });
  });
}
