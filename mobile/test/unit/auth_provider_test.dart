import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';

class _MockAuthService extends Mock implements AuthServiceInterface {}

void main() {
  late _MockAuthService service;

  setUpAll(() {
    service = _MockAuthService();
    serviceLocator.authService = service;
  });

  setUp(() {
    reset(service);
    when(() => service.getCurrentUser()).thenAnswer((_) async => null);
  });

  test('verifyOtp surfaces the failure code on a locked error', () async {
    when(() => service.verifyOtp(any(), any())).thenAnswer(
      (_) async => ApiResponse<User>.error(
        'Trop de tentatives.',
        code: 'otp_locked',
      ),
    );

    final provider = AuthProvider();
    final ok = await provider.verifyOtp('+2250700000000', '000000');

    expect(ok, isFalse);
    expect(provider.otpErrorCode, 'otp_locked');
    expect(provider.error, isNotNull);
  });

  test('a successful verifyOtp clears the failure code', () async {
    when(() => service.verifyOtp(any(), any())).thenAnswer(
      (_) async => ApiResponse.success(
        User(
          id: 'u1',
          phoneNumber: '+2250700000000',
          createdAt: DateTime(2024),
        ),
      ),
    );

    final provider = AuthProvider();
    final ok = await provider.verifyOtp('+2250700000000', '123456');

    expect(ok, isTrue);
    expect(provider.otpErrorCode, isNull);
  });
}
