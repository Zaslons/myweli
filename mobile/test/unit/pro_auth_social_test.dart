import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';

/// Pro auth overhaul P4 (docs/design/pro-auth-social.md): LOGIN-ONLY social +
/// email OTP, and registration = identity + business fields in ONE submit.
void main() {
  group('MockAuthService — pro social + email', () {
    // NOTE: mock salons live in static MockData.providerUsers, so within this
    // file the login-only assertions run BEFORE any register creates accounts.
    test(
        'social login is LOGIN-ONLY: no salon → provider_not_found, no session',
        () async {
      final service = MockAuthService();
      final res = await service.signInProviderWithGoogle();
      expect(res.success, isFalse);
      expect(res.code, 'provider_not_found');
      expect(await service.getCurrentProvider(), isNull);
    });

    test(
        'email OTP login keeps the code on provider_not_found so register '
        'can reuse it (one code, one flow)', () async {
      final service = MockAuthService();
      final sent = await service.requestProviderEmailOtp('New@Salon.test');
      expect(sent.success, isTrue);
      expect(sent.data, MockAuthService.demoOtp);

      final wrong =
          await service.verifyProviderEmailOtp('new@salon.test', '000000');
      expect(wrong.success, isFalse);
      expect(wrong.code, 'otp_invalid');

      final notFound = await service.verifyProviderEmailOtp(
          'new@salon.test', MockAuthService.demoOtp);
      expect(notFound.success, isFalse);
      expect(notFound.code, 'provider_not_found');

      // The unconsumed code registers the salon — and signs it in.
      final reg = await service.registerProviderWithEmail(
        email: 'new@salon.test',
        code: MockAuthService.demoOtp,
        phoneNumber: '+2250700000010',
        businessName: 'Salon Nouveau',
        businessType: BusinessType.salon,
        address: 'Cocody',
      );
      expect(reg.success, isTrue);
      expect(reg.data!.email, 'new@salon.test');
      expect(reg.data!.phoneNumber, '+2250700000010');
      expect((await service.getCurrentProvider())!.id, reg.data!.id);

      // The code was consumed by register.
      final replay = await service.verifyProviderEmailOtp(
          'new@salon.test', MockAuthService.demoOtp);
      expect(replay.success, isFalse);
      expect(replay.code, 'otp_invalid');
    });

    test('email register: duplicate identity → provider_exists', () async {
      final service = MockAuthService();
      await service.requestProviderEmailOtp('dup@salon.test');
      await service.registerProviderWithEmail(
        email: 'dup@salon.test',
        code: MockAuthService.demoOtp,
        phoneNumber: '+2250700000011',
        businessName: 'Salon A',
        businessType: BusinessType.salon,
      );

      await service.requestProviderEmailOtp('dup@salon.test');
      final again = await service.registerProviderWithEmail(
        email: 'dup@salon.test',
        code: MockAuthService.demoOtp,
        phoneNumber: '+2250700000012',
        businessName: 'Salon B',
        businessType: BusinessType.barber,
      );
      expect(again.success, isFalse);
      expect(again.code, 'provider_exists');
    });

    test('register with Google signs in; the same identity then logs in',
        () async {
      final service = MockAuthService();
      final reg = await service.registerProviderWithGoogle(
        phoneNumber: '+2250700000013',
        businessName: 'Salon Google',
        businessType: BusinessType.spa,
      );
      expect(reg.success, isTrue);
      expect(reg.data!.email, MockAuthService.mockProGoogleEmail);
      expect((await service.getCurrentProvider())!.id, reg.data!.id);

      // Duplicate register → provider_exists.
      final dup = await service.registerProviderWithGoogle(
        phoneNumber: '+2250700000014',
        businessName: 'Salon Google 2',
        businessType: BusinessType.spa,
      );
      expect(dup.success, isFalse);
      expect(dup.code, 'provider_exists');

      // Login now resolves to the SAME salon.
      await service.logoutProvider();
      final login = await service.signInProviderWithGoogle();
      expect(login.success, isTrue);
      expect(login.data!.id, reg.data!.id);
    });
  });

  group('ProAuthProvider — pro social + email', () {
    setUpAll(() {
      serviceLocator.authService = MockAuthService();
    });

    test(
        'login-only Google failure surfaces errorCode provider_not_found '
        'for the « Créer un compte » CTA', () async {
      final provider = ProAuthProvider();
      // The Google mock identity was registered in the group above only for
      // THAT service instance's static MockData — reuse a fresh email path.
      final ok = await provider.verifyEmailOtp('ghost@salon.test', '000000');
      expect(ok, isFalse);
      expect(provider.errorCode, 'otp_invalid');

      await provider.requestEmailOtp('ghost@salon.test');
      final notFound = await provider.verifyEmailOtp(
          'ghost@salon.test', provider.emailDevCode!);
      expect(notFound, isFalse);
      expect(provider.errorCode, 'provider_not_found');
      expect(provider.isAuthenticated, isFalse);
    });

    test('requestEmailOtp exposes the dev code; registerWithEmail signs in',
        () async {
      final provider = ProAuthProvider();
      expect(await provider.requestEmailOtp('flow@salon.test'), isTrue);
      expect(provider.emailDevCode, MockAuthService.demoOtp);

      final ok = await provider.registerWithEmail(
        email: 'flow@salon.test',
        code: provider.emailDevCode!,
        phoneNumber: '+2250700000015',
        businessName: 'Salon Flow',
        businessType: BusinessType.nailSalon,
        address: 'Marcory',
      );
      expect(ok, isTrue);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.provider!.businessName, 'Salon Flow');
      expect(provider.provider!.phoneNumber, '+2250700000015');
    });

    test('email login works after registration', () async {
      final provider = ProAuthProvider();
      await provider.requestEmailOtp('flow@salon.test');
      final ok = await provider.verifyEmailOtp(
          'flow@salon.test', provider.emailDevCode!);
      expect(ok, isTrue);
      expect(provider.provider!.email, 'flow@salon.test');
    });
  });
}
