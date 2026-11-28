import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/pro_app_extensions.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/android/pro_android_extensions.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/golden.dart';
import '../support/pro_sign_up.dart';

/// Android's sign-in and sign-up, photographed at the floor — 360dp, 200%
/// text, where a chip, a heading or a button runs out of room first
/// (docs/design/pro-android-signup.md §8.2 « Goldens »).
///
/// `pro_login_w360_x2` (pro_screens_golden_test) is the iOS sign-in: it mounts
/// no block and must stay byte-identical. These are the Android one, with it.
void main() {
  group('goldens', () {
    final mock = MockAuthService();

    setUpAll(() async {
      AppClock.freeze(kFixedNow);
      await initializeDateFormatting('fr_FR', null);
      SharedPreferences.setMockInitialValues({});
      serviceLocator
        ..authService = mock
        ..proService = MockProService()
        ..proTeamService = MockProTeamService()
        ..proPushRegistration = PushRegistration(
          push: MockPushNotificationService(),
          devices: MockDeviceRegistrationService(),
        );
      await loadRealFonts();
    });
    tearDownAll(AppClock.restore);

    setUp(() async {
      MockData.resetTeam();
      mock.proGoogleEmail = 'golden.nouveau@salon.test';
      await mock.logoutProvider();
    });

    Future<void> pumpAndroid(
      WidgetTester tester, {
      double height = 1400,
    }) async {
      goldenSurface(tester, size: Size(360, height), scale: 2);
      final android = proAndroidExtensionsFor(TargetPlatform.android)!;
      final router = GoRouter(
        initialLocation: '/pro/login',
        routes: [
          GoRoute(
            path: '/pro/login',
            builder: (_, _) => const ProLoginScreen(),
          ),
          ...android.routes,
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ProAuthProvider(router: router),
            ),
            Provider<ProLoginExtras?>.value(value: android.login),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: goldenTheme(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('fr', 'FR')],
            locale: const Locale('fr', 'FR'),
            routerConfig: router,
          ),
        ),
      );
      await settleMocks(tester, rounds: 3);
    }

    Future<void> openSignUp(WidgetTester tester) async {
      final button = find.text('Créer le compte de mon salon');
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settleMocks(tester, rounds: 3);
      // The top of the form: the picture starts where the person does.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 4000));
      await settleMocks(tester);
    }

    Future<void> tapVisible(WidgetTester tester, String text) async {
      final target = find.text(text);
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await settleMocks(tester, rounds: 4);
    }

    testWidgets('the Android sign-in, its block (E1)', (tester) async {
      await pumpAndroid(tester);
      expect(find.text('Pas encore de compte ?'), findsOneWidget);
      await expectGolden(tester, 'pro_login_android_w360_x2');
    });

    testWidgets('the Android sign-in after « Aucun compte » (E2)', (
      tester,
    ) async {
      await pumpAndroid(tester);
      await tapVisible(tester, 'Continuer avec Google');
      expect(find.text(kNoProAccountMessage), findsOneWidget);
      await expectGolden(tester, 'pro_login_android_not_found_w360_x2');
    });

    testWidgets('the sign-up, empty', (tester) async {
      await pumpAndroid(tester, height: 3600);
      await openSignUp(tester);
      expect(find.text('Votre identité de connexion'), findsOneWidget);
      await expectGolden(tester, 'pro_sign_up_w360_x2');
    });

    testWidgets('the sign-up, every field\'s fault', (tester) async {
      await pumpAndroid(tester, height: 3800);
      await openSignUp(tester);
      await tapVisible(tester, 'Continuer avec Google');
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 4000));
      await settleMocks(tester);
      expect(find.text('Choisissez le type d’entreprise.'), findsOneWidget);
      await expectGolden(tester, 'pro_sign_up_faults_w360_x2');
    });

    testWidgets('the sign-up, invitations found (S4)', (tester) async {
      mock.proGoogleEmail = MockAuthService.mockProGoogleEmail;
      await pumpAndroid(tester, height: 1800);
      await openSignUp(tester);
      await tester.enterText(find.byType(TextField).first, 'Salon Awa');
      await tapVisible(tester, 'Spa');
      await tester.enterText(find.byType(TextField).at(1), '0707010101');
      await tester.enterText(find.byType(TextField).at(2), 'Rue des Jardins');
      await tester.pump();
      await tapVisible(tester, 'Continuer avec Google');
      expect(find.text('Vous êtes invité(e)'), findsOneWidget);
      await expectGolden(tester, 'pro_sign_up_invited_w360_x2');
    });

    // docs/design/app-pro-profile-email-seams.md §6: E3 at §13.3's contract
    // point. The sign-in by e-mail found no account, and the sign-up carries
    // that address: « Compte : », then the address on a line of its own —
    // « awa.kone.nouvelle » / « @outlook.com ». Inline, it read « Compte :
    // awa.kone.n » / « ouvelle@outlook.co » / « m ».
    testWidgets('the sign-up from E3, the carried address', (tester) async {
      const address = 'awa.kone.nouvelle@outlook.com';
      await pumpAndroid(tester, height: 3600);
      await tester.enterText(input('Votre e-mail'), address);
      await tapVisible(tester, 'Continuer avec e-mail');
      await tester.enterText(
        input('Code à 6 chiffres'),
        MockAuthService.demoOtp,
      );
      await tapVisible(tester, 'Se connecter');
      expect(find.text(kNoProAccountMessage), findsOneWidget);
      await openSignUp(tester);
      expect(find.text('Compte :'), findsOneWidget, reason: 'E3');
      await expectGolden(tester, 'pro_sign_up_carried_w360_x2');
    });
  }, skip: kGoldensSkip);
}
