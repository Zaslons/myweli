import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/screens/profile/edit_profile_screen.dart';
import 'package:myweli/screens/profile/email_change_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/golden.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';

/// « Modifier le profil »'s address row and « Changer d’adresse e-mail »
/// (B16.3b — docs/design/account-email-change.md §5.4, §8.2: « a golden of
/// each step »), at the floor and 200 % text — where a long address, two code
/// fields and their sentences have to fit.
///
/// Signed in by an e-mail code, so the address is proven AND the account's
/// only way in: the code step asks for both codes (decision 265), the
/// heaviest it gets.
void main() {
  group('goldens', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      stubSecureStorage();
      setupDependencyInjection(); // every service, all mocks
      await loadRealFonts();
    });

    const email = 'awa.kone@exemple.ci';
    const next = 'awa.kone.nouvelle@exemple.ci';

    Future<void> pumpProfile(WidgetTester tester) async {
      goldenSurface(tester, size: const Size(360, 1400), scale: 2);
      late final AuthProvider auth;
      await tester.runAsync(() async {
        final mock = serviceLocator.authService as MockAuthService;
        await mock.requestEmailOtp(email);
        final res = await mock.verifyEmailOtp(email, MockAuthService.demoOtp);
        expect(res.success, isTrue);
        auth = AuthProvider();
        for (var i = 0; i < 60 && auth.isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(auth.user?.email, email);
      final router = GoRouter(
        initialLocation: '/profile/edit',
        routes: [
          GoRoute(
            path: '/profile/edit',
            builder: (_, _) => const EditProfileScreen(),
            routes: [
              GoRoute(
                path: 'email',
                builder: (_, _) => const EmailChangeScreen(),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
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
      await settleMocks(tester, rounds: 2);
    }

    Future<void> openChange(WidgetTester tester) async {
      await tester.tap(find.text('Modifier'));
      await settleMocks(tester, rounds: 2);
      expect(find.text('Nouvelle adresse e-mail'), findsOneWidget);
    }

    testWidgets('the address row, proven, at 200% text', (tester) async {
      await pumpProfile(tester);
      expect(find.text(email), findsOneWidget);
      await expectGolden(tester, 'consumer_edit_profile_email_w360_x2');
    });

    testWidgets('the address step, at 200% text', (tester) async {
      await pumpProfile(tester);
      await openChange(tester);
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(AppTextField, 'Nouvelle adresse e-mail'),
          matching: find.byType(TextField),
        ),
        next,
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await expectGolden(tester, 'consumer_email_change_address_w360_x2');
    });

    testWidgets('the code step, both codes, at 200% text', (tester) async {
      await pumpProfile(tester);
      await openChange(tester);
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(AppTextField, 'Nouvelle adresse e-mail'),
          matching: find.byType(TextField),
        ),
        next,
      );
      await tester.pump();
      await tester.tap(find.text('Recevoir un code'));
      await settleMocks(tester, rounds: 2);
      expect(
        find.text('Code de l’adresse actuelle'),
        findsOneWidget,
        reason: 'an e-mail-code account: the second code (decision 265)',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await expectGolden(tester, 'consumer_email_change_codes_w360_x2');
    });
  }, skip: kGoldensSkip);
}
