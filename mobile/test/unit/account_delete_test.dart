import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';

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
      when(() => service.deleteAccount())
          .thenAnswer((_) async => ApiResponse.success(null));

      final provider = AuthProvider();
      final ok = await provider.deleteAccount();

      expect(ok, isTrue);
      expect(provider.user, isNull);
      expect(provider.isAuthenticated, isFalse);
    });

    test('returns false and surfaces the error on failure', () async {
      when(() => service.deleteAccount())
          .thenAnswer((_) async => ApiResponse.error('boom'));

      final provider = AuthProvider();
      final ok = await provider.deleteAccount();

      expect(ok, isFalse);
      expect(provider.error, 'boom');
    });
  });
}
