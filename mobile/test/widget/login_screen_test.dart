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

import '../support/pump_app.dart';

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
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );
    return wrapApp(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      routerConfig: router,
    );
  }

  /// Advance past the mock latency without pumpAndSettle (the brand loader
  /// animates forever, so pumpAndSettle would never settle mid-load).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('options step: Google + email visible, Apple hidden (flag off)', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Continuer avec Google'), findsOneWidget);
    // Google's branding guidelines: the official « G » sits on the button.
    expect(find.byType(GoogleGLogo), findsOneWidget);
    expect(find.text('Continuer avec e-mail'), findsOneWidget);
    expect(find.text('Continuer avec Apple'), findsNothing);
  });

  testWidgets('email login: code step → verify → MANDATORY phone step → home', (
    tester,
  ) async {
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

  /// A7-fix — **the per-funnel gate §20 claims, made real for this funnel.**
  ///
  /// A7 declared a `'phone'` rule on this screen, bound `errorText` to it, wired
  /// `revalidate` — and never called `validate`. It also deleted the
  /// `_phoneNumber.isEmpty` gate that had been holding the step, under §14
  /// rule 5. Net: one tap on « Continuer » with an empty field saved an EMPTY
  /// phone (the backend documents `''` as "clear it") and landed on /home,
  /// through the app's only enforcement of the mandatory contact number.
  ///
  /// The shape asserted here is the one §14 actually specifies, and it is what
  /// every funnel test in this repo should hold: **the press answers, under the
  /// field · no `SnackBar` (rule 3) · the flow does not advance · fixing it
  /// clears the message without a second submit (rule 2)**.
  testWidgets('the MANDATORY phone step answers an empty submit — it does not '
      'let it through', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Continuer avec Google'));
    await settle(tester);
    expect(find.text('Votre numéro de téléphone'), findsOneWidget);

    // Press with nothing typed. Rule 5 means the button is live, so it MUST
    // answer rather than silently succeed.
    await tester.tap(find.text('Continuer'));
    await settle(tester);
    await settle(tester);

    expect(
      find.text('Saisissez un numéro de téléphone.'),
      findsOneWidget,
      reason: 'the fault renders under the field it belongs to (§14 rule 1)',
    );
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '§14 rule 3 — a field fault is never a bar',
    );
    expect(
      find.text('HOME'),
      findsNothing,
      reason: 'and above all it must not walk through the mandatory step',
    );

    // Rule 2: fixing it clears the message without another submit.
    await tester.enterText(find.byType(TextField).first, '0700000001');
    await tester.pump();
    expect(find.text('Saisissez un numéro de téléphone.'), findsNothing);
  });

  testWidgets('google login also lands on the phone step (no phone yet)', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Continuer avec Google'));
    await settle(tester);

    expect(find.text('Votre numéro de téléphone'), findsOneWidget);
  });
}
