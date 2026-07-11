import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/widgets/common/google_g_logo.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auth overhaul P3 (docs/design/app-auth-social.md): the LoginScreen flow —
/// options → email code → MANDATORY contact phone → returnTo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Advance past the mock latency without pumpAndSettle (the brand loader
  /// animates forever, so pumpAndSettle would never settle mid-load).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('options step: Google + email visible, Apple hidden (flag off)',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Continuer avec Google'), findsOneWidget);
    // Google's branding guidelines: the official « G » sits on the button.
    expect(find.byType(GoogleGLogo), findsOneWidget);
    expect(find.text('Continuer avec e-mail'), findsOneWidget);
    expect(find.text('Continuer avec Apple'), findsNothing);
  });

  testWidgets('email login: code step → verify → MANDATORY phone step → home',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    // Enter the email and request the code.
    await tester.enterText(find.byType(TextField).first, 'awa@test.com');
    await tester.pump();
    await tester.tap(find.text('Continuer avec e-mail'));
    await settle(tester);

    // Code step, with the mock dev code hinted.
    expect(find.textContaining('Entrez le code reçu'), findsOneWidget);
    expect(find.textContaining('Code (dev)'), findsOneWidget);

    // Resend (module 11): counting down and disabled, then active after 60 s.
    expect(find.textContaining('Renvoyer le code ('), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Renvoyer le code'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      MockAuthService.demoOtp,
    );
    await tester.pump();
    await tester.tap(find.text('Se connecter'));
    await settle(tester);

    // Fresh account has no phone → the mandatory contact-phone step blocks.
    expect(find.text('Votre numéro de téléphone'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    // Enter a CI number → saved as contact → continue to home.
    await tester.enterText(find.byType(TextField).first, '0700000001');
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await settle(tester);
    await settle(tester);

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('google login also lands on the phone step (no phone yet)',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Continuer avec Google'));
    await settle(tester);

    expect(find.text('Votre numéro de téléphone'), findsOneWidget);
  });
}
