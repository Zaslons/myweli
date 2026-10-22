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
      (_) async =>
          ApiResponse<User>.error('Trop de tentatives.', code: 'otp_locked'),
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

  // hygiene-batch9.md §2.6 (B9.7) — the sign-in places its sentence by this
  // code (sign_in_refusal.dart): a send that throws after a refused code must
  // not keep « otp_invalid », or the screen hides the new failure as the
  // code's.
  test('a new attempt starts without the last one\'s code', () async {
    when(() => service.verifyEmailOtp(any(), any())).thenAnswer(
      (_) async =>
          ApiResponse<User>.error('Code incorrect.', code: 'otp_invalid'),
    );
    when(() => service.requestEmailOtp(any())).thenThrow(StateError('boom'));

    final provider = AuthProvider();
    await provider.verifyEmailOtp('a@b.ci', '000000');
    expect(provider.otpErrorCode, 'otp_invalid', reason: 'the scenario');

    await provider.requestEmailOtp('a@b.ci');
    expect(provider.otpErrorCode, isNull);
    expect(provider.error, isNotNull);
  });

  test('…and a sign-in that throws likewise', () async {
    when(() => service.verifyEmailOtp(any(), any())).thenAnswer(
      (_) async =>
          ApiResponse<User>.error('Code incorrect.', code: 'otp_invalid'),
    );
    final provider = AuthProvider();
    await provider.verifyEmailOtp('a@b.ci', '000000');

    when(() => service.verifyEmailOtp(any(), any())).thenThrow(StateError('x'));
    await provider.verifyEmailOtp('a@b.ci', '111111');
    expect(provider.otpErrorCode, isNull);
  });
}
