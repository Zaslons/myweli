import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/config/app_config.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:myweli/widgets/common/inline_feedback.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// docs/design/pro-app-login-only.md (B0.11) — Apple refused MyWeli Pro 0.0.1
/// under 3.1.1: « Remove the account registration features for business and
/// organizations ». The Pro app signs salons IN; it no longer signs them up
/// or creates salons. Sign-up and « Ajouter un salon » live on myweli.com,
/// and the login screen's « S’inscrire sur myweli.com » opens it in the
/// browser (the owner's call, §3 Q5). Invitations stay.
void main() {
  /// Every Dart file under `lib/`, `//` and `/* */` comments removed — the
  /// comments here and in the code quote the removed copy to explain it.
  Map<String, String> code() => {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path: f
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n'),
  };

  group('nothing in the app signs a business up', () {
    test('the routes are gone', () {
      final router = code()['lib/core/router/pro_router.dart']!;
      expect(router, isNot(contains("'/pro/register'")));
      expect(router, isNot(contains("'/pro/salons/nouveau'")));
    });

    test('the two screens are gone, not just unrouted', () {
      expect(
        File('lib/screens/provider/auth/pro_register_screen.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/screens/provider/salons/add_salon_screen.dart').existsSync(),
        isFalse,
      );
    });

    test('no code path registers an account or creates a salon', () {
      final calls = RegExp(
        r'\b(registerProviderWith(Google|Apple|Email)|'
        r'registerWith(Google|Apple|Email)|addSalon)\s*\(',
      );
      final found = <String>[
        for (final e in code().entries)
          if (calls.hasMatch(e.value)) e.key,
      ];
      expect(
        found,
        isEmpty,
        reason:
            'POST /auth/provider/register* and '
            'POST /me/salons are the web\'s alone',
      );
    });

    test('no copy offers to sign up or to add a salon', () {
      // `Créer un compte` is not in the list: the CONSUMER app registers its
      // clients, and that is not what Apple named.
      const removed = [
        'Inscription Pro',
        'S’inscrire avec',
        'Ajouter un salon',
        'Inscrivez-vous',
        'Créez votre compte',
      ];
      final hits = <String>[
        for (final e in code().entries)
          for (final phrase in removed)
            if (e.value.contains(phrase)) '${e.key}: « $phrase »',
      ];
      expect(hits, isEmpty);
    });

    test('the Pro surfaces never say « Créer un compte »', () {
      final hits = <String>[
        for (final e in code().entries)
          if ((e.key.contains('/screens/provider/') ||
                  e.key.contains('/widgets/provider/') ||
                  e.key.contains('/widgets/team/')) &&
              e.value.contains('Créer un compte'))
            e.key,
      ];
      expect(hits, isEmpty);
    });
  });

  group('the sign-up link goes to the web', () {
    test('its destination is the web sign-up, a page that exists', () {
      expect(
        AppConfig.proSignUpUrl,
        '${AppConfig.siteBaseUrl}/pro/inscription',
      );
      expect(
        File('../web/app/pro/inscription/page.tsx').existsSync(),
        isTrue,
        reason: 'the link must land on a real page',
      );
    });
  });

  group('the login screen', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    late List<Map<Object?, Object?>> launched;

    setUpAll(() async {
      await initializeDateFormatting('fr_FR', null);
      SharedPreferences.setMockInitialValues({});
      serviceLocator.authService = MockAuthService();
      serviceLocator.proService = MockProService();
    });

    setUp(() async {
      MockData.resetTeam();
      await serviceLocator.authService.logoutProvider();
      launched = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'launch') {
              launched.add(call.arguments as Map<Object?, Object?>);
            }
            return true;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    Widget app() => wrapApp(
      providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
      routerConfig: GoRouter(
        initialLocation: '/pro/login',
        routes: [
          GoRoute(
            path: '/pro/login',
            builder: (_, _) => const ProLoginScreen(),
          ),
          GoRoute(
            path: '/pro/dashboard',
            builder: (_, _) => const Scaffold(body: Text('DASHBOARD')),
          ),
        ],
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Finder input(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
      matching: find.byType(TextField),
    );

    testWidgets('« S’inscrire sur myweli.com » opens the web sign-up in the '
        'browser, and goes nowhere in the app', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('Pas encore de compte ?'), findsOneWidget);
      await tester.ensureVisible(find.text('S’inscrire sur myweli.com'));
      await tester.tap(find.text('S’inscrire sur myweli.com'));
      await settle(tester);

      expect(launched, hasLength(1));
      expect(launched.single['url'], 'https://myweli.com/pro/inscription');
      // LaunchMode.externalApplication: neither Safari's view nor a web view.
      expect(launched.single['useSafariVC'], isFalse);
      expect(launched.single['useWebView'], isFalse);
      expect(find.byType(ProLoginScreen), findsOneWidget);
    });

    testWidgets('a sign-in with no account says so, with the invitation hint, '
        'and offers no way to create one in the app', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.enterText(input('Votre e-mail'), 'inconnu@salon.test');
      await tester.pump();
      await tester.tap(find.text('Continuer avec e-mail'));
      await settle(tester);
      await tester.enterText(
        input('Code à 6 chiffres'),
        MockAuthService.demoOtp,
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.text('Se connecter'));
      await settle(tester);

      expect(
        find.descendant(
          of: find.byType(InlineFeedback),
          matching: find.text(
            'Aucun compte MyWeli Pro n’est associé à cette adresse. Si votre '
            'salon vous a invité, connectez-vous avec l’adresse qui a reçu '
            'l’invitation.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Créer un compte'), findsNothing);
    });
  });
}
