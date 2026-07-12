import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Team access R4b §5.3 — revoked mid-session: a forbidden response probes
/// the membership once, signs the member out, and the login screen shows
/// « Votre accès à {Salon} a été retiré. » (no dead-end screens).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = MockAuthService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = MockProService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    await auth.logoutProvider();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets(
      'revoked → guard probe → sign-out → the login banner names '
      'the salon', (tester) async {
    // FakeAsync-safe: the whole pre-pump flow uses REAL async (mock
    // delays + the guard's probe) inside runAsync.
    late ProAuthProvider authProvider;
    await tester.runAsync(() async {
      // Sign in as the seeded réception member.
      await auth.requestProviderEmailOtp('fatou.reception@myweli.test');
      await auth.verifyProviderEmailOtp(
        'fatou.reception@myweli.test',
        MockAuthService.demoOtp,
      );

      authProvider = ProAuthProvider();
      // Let the constructor's load + membership refresh land.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(authProvider.isAuthenticated, isTrue);

      // The owner revokes fatou; her next 403 hits the guard.
      final i =
          MockData.teamMembers.indexWhere((m) => m.id == 'mem_reception2');
      MockData.teamMembers[i] = MockData.teamMembers[i].copyWith(
        status: TeamMemberStatus.revoked,
        revokedAt: DateTime.now(),
      );
      ProAccessGuard.report('forbidden');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(authProvider.isAuthenticated, isFalse);
    });

    // The login screen consumes the one-shot notice into the banner.
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: authProvider,
        child: const MaterialApp(home: ProLoginScreen()),
      ),
    );
    await settle(tester);

    expect(
      find.text('Votre accès à Salon Excellence a été retiré.'),
      findsOneWidget,
    );
    // Consumed: a rebuilt login screen shows no banner.
    expect(authProvider.consumeRevokedNotice(), isNull);
  });
}
