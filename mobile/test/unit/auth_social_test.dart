import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';

/// Auth overhaul P3 (docs/design/app-auth-social.md): Google/Apple/email login
/// on the mock service + AuthProvider, incl. the contact-phone rules.
void main() {
  group('MockAuthService — social + email login', () {
    test('signInWithGoogle creates a user WITHOUT a phone (step follows)',
        () async {
      final service = MockAuthService();
      final res = await service.signInWithGoogle();
      expect(res.success, isTrue);
      expect(res.data!.email, 'mock.google@myweli.test');
      expect(res.data!.authProvider, 'google');
      expect(res.data!.phoneNumber, isNull);
      expect(res.data!.phoneVerified, isFalse);
    });

    test('same Google identity resolves to the same user', () async {
      final service = MockAuthService();
      final a = (await service.signInWithGoogle()).data!;
      final b = (await service.signInWithGoogle()).data!;
      expect(b.id, a.id);
    });

    test('email OTP: request → verify creates the user by email', () async {
      final service = MockAuthService();
      final sent = await service.requestEmailOtp('Ama@Test.com');
      expect(sent.success, isTrue);
      expect(sent.data, MockAuthService.demoOtp);

      final res = await service.verifyEmailOtp('ama@test.com', sent.data!);
      expect(res.success, isTrue);
      expect(res.data!.email, 'ama@test.com');
      expect(res.data!.authProvider, 'email');
      expect(await service.getCurrentUser(), isNotNull);
    });

    test('email OTP: wrong code → otp_invalid; right code still works',
        () async {
      final service = MockAuthService();
      await service.requestEmailOtp('a@test.com');
      final wrong = await service.verifyEmailOtp('a@test.com', '000000');
      expect(wrong.success, isFalse);
      expect(wrong.code, 'otp_invalid');
      final right =
          await service.verifyEmailOtp('a@test.com', MockAuthService.demoOtp);
      expect(right.success, isTrue);
    });

    test('updateUser(phone:) sets an UNVERIFIED contact phone; empty clears',
        () async {
      final service = MockAuthService();
      await service.signInWithGoogle();

      final withPhone = await service.updateUser(phone: '+2250700000001');
      expect(withPhone.data!.phoneNumber, '+2250700000001');
      expect(withPhone.data!.phoneVerified, isFalse);

      final cleared = await service.updateUser(phone: '');
      expect(cleared.data!.phoneNumber, isNull);
    });
  });

  group('AuthProvider — social + email login', () {
    setUpAll(() {
      serviceLocator.authService = MockAuthService();
    });

    test('signInWithGoogle authenticates', () async {
      final provider = AuthProvider();
      final ok = await provider.signInWithGoogle();
      expect(ok, isTrue);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.user!.authProvider, 'google');
    });

    test('requestEmailOtp exposes the dev code; verify signs in', () async {
      final provider = AuthProvider();
      expect(await provider.requestEmailOtp('flow@test.com'), isTrue);
      expect(provider.emailDevCode, MockAuthService.demoOtp);

      final ok = await provider.verifyEmailOtp(
        'flow@test.com',
        provider.emailDevCode!,
      );
      expect(ok, isTrue);
      expect(provider.user!.email, 'flow@test.com');
    });

    test('wrong email code surfaces the error + code', () async {
      final provider = AuthProvider();
      await provider.requestEmailOtp('err@test.com');
      final ok = await provider.verifyEmailOtp('err@test.com', '000000');
      expect(ok, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.otpErrorCode, 'otp_invalid');
    });

    test('updateUser(phone:) updates the user', () async {
      final provider = AuthProvider();
      await provider.signInWithGoogle();
      final ok = await provider.updateUser(phone: '+2250700000002');
      expect(ok, isTrue);
      expect(provider.user!.phoneNumber, '+2250700000002');
      expect(provider.user!.phoneVerified, isFalse);
    });
  });
}
