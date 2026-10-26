import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_login_result.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';

import '../support/web_created.dart';

/// Pro auth overhaul P4 (docs/design/pro-auth-social.md): LOGIN-ONLY social +
/// email OTP, registration = identity + business fields in ONE submit — and
/// the R3 invitation bridge (a verified email with pending invitations gets
/// the `.invited` outcome instead of provider_not_found).
void main() {
  setUp(MockData.resetTeam);

  group('MockAuthService — pro social + email', () {
    // NOTE: mock salons live in static MockData.providerUsers, so within this
    // file the login-only assertions run BEFORE any register creates accounts.
    test('Google login with no account but a PENDING invitation → the '
        'invited outcome (the 202 bridge), session untouched', () async {
      final service = MockAuthService();
      final res = await service.signInProviderWithGoogle();
      expect(res.signedIn, isFalse);
      expect(res.hasInvitations, isTrue);
      expect(res.invitations.single.salonName, 'Beauté Divine');
      expect(res.proof, isA<GoogleInvitationProof>());
      expect(await service.getCurrentProvider(), isNull);
    });

    test('Apple login is LOGIN-ONLY with NO bridge: no salon → '
        'provider_not_found, no session', () async {
      final service = MockAuthService();
      final res = await service.signInProviderWithApple();
      expect(res.signedIn, isFalse);
      expect(res.hasInvitations, isFalse);
      expect(res.code, 'provider_not_found');
      expect(await service.getCurrentProvider(), isNull);
    });
  });

  group('ProAuthProvider — pro social + email', () {
    setUpAll(() {
      serviceLocator.authService = MockAuthService();
    });

    test(
      'login-only failure surfaces errorCode provider_not_found and the '
      'one no-account sentence (no sign-up in the app — App Store 3.1.1)',
      () async {
        final provider = ProAuthProvider();
        // The Google mock identity was registered in the group above only for
        // THAT service instance's static MockData — reuse a fresh email path.
        final ok = await provider.verifyEmailOtp('ghost@salon.test', '000000');
        expect(ok, isFalse);
        expect(provider.errorCode, 'otp_invalid');

        await provider.requestEmailOtp('ghost@salon.test');
        final notFound = await provider.verifyEmailOtp(
          'ghost@salon.test',
          provider.emailDevCode!,
        );
        expect(notFound, isFalse);
        expect(provider.errorCode, 'provider_not_found');
        expect(provider.error, kNoProAccountMessage);
        expect(provider.isAuthenticated, isFalse);
      },
    );

    test('requestEmailOtp exposes the dev code; a salon signed up on the web '
        'signs in with it', () async {
      // Signed up on the web — the app no longer registers a business
      // (App Store 3.1.1, docs/design/pro-app-login-only.md).
      seedWebSignUp(
        email: 'flow@salon.test',
        phoneNumber: '+2250700000015',
        businessName: 'Salon Flow',
        businessType: BusinessType.nailSalon,
        address: 'Marcory',
      );
      final provider = ProAuthProvider();
      expect(await provider.requestEmailOtp('flow@salon.test'), isTrue);
      expect(provider.emailDevCode, MockAuthService.demoOtp);

      final ok = await provider.verifyEmailOtp(
        'flow@salon.test',
        provider.emailDevCode!,
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
        'flow@salon.test',
        provider.emailDevCode!,
      );
      expect(ok, isTrue);
      expect(provider.provider!.email, 'flow@salon.test');
    });
  });
}
