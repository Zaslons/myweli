import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider_login_result.dart';
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

/// docs/design/hygiene-batch9.md §2.6 (B9.7) — the salon sign-in's faults,
/// each under the field it belongs to (SYSTEM.md §14 rule 1).
///
/// The local rules (an empty or malformed e-mail, a code that is not six
/// digits) answer under their field and send nothing. A refusal the SERVER
/// gives the code or the e-mail goes under that field too, as on the web
/// (web-client-polish.md §2.1, Q1; sign_in_refusal.dart) — the app said all
/// of them under the form. What is no field's stays under the form.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final auth = _ScriptedAuth();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = MockProService(); // membership refresh (R4b)
  });

  setUp(() async {
    MockData.resetTeam();
    auth
      ..sendRefusal = null
      ..codeRefusal = null
      ..sends = 0
      ..verifies = 0;
    await auth.logoutProvider();
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/pro/login',
      routes: [
        GoRoute(path: '/pro/login', builder: (_, _) => const ProLoginScreen()),
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, _) => const Scaffold(body: Text('DASHBOARD')),
        ),
        GoRoute(
          path: '/pro/register',
          builder: (_, _) => const Scaffold(body: Text('REGISTER')),
        ),
      ],
    );
    return wrapApp(
      providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
      routerConfig: router,
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Finder field(String label) =>
      find.byWidgetPredicate((w) => w is AppTextField && w.label == label);
  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(TextField));
  Finder under(String label, String message) =>
      find.descendant(of: field(label), matching: find.text(message));
  Finder underTheForm(String message) => find.descendant(
    of: find.byType(InlineFeedback),
    matching: find.text(message),
  );
  bool focused(WidgetTester tester, String label) => tester
      .widget<EditableText>(
        find.descendant(of: field(label), matching: find.byType(EditableText)),
      )
      .focusNode
      .hasFocus;

  Future<void> sendFor(WidgetTester tester, String email) async {
    await tester.enterText(input('Votre e-mail'), email);
    await tester.pump();
    await tester.tap(find.text('Continuer avec e-mail'));
    await settle(tester);
  }

  Future<void> toCodeStep(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await sendFor(tester, 'jean@salon-excellence.test');
    expect(field('Code à 6 chiffres'), findsOneWidget, reason: 'the scenario');
  }

  Future<void> submitCode(WidgetTester tester, String code) async {
    await tester.enterText(input('Code à 6 chiffres'), code);
    await tester.pump();
    // The keyboard dismissed before the press, as a user does: the field
    // keeps no focus of its own, so a fault that takes it is seen taking it.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
  }

  group('the local rules', () {
    testWidgets('an empty e-mail: said under the field, focused, nothing '
        'sent; typing a real one clears it', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.tap(find.text('Continuer avec e-mail'));
      await settle(tester);

      expect(under('Votre e-mail', 'Saisissez une adresse e-mail.'), findsOne);
      expect(focused(tester, 'Votre e-mail'), isTrue);
      expect(auth.sends, 0);
      expect(find.byType(SnackBar), findsNothing);

      await tester.enterText(input('Votre e-mail'), 'jean@');
      await tester.pump();
      expect(
        under('Votre e-mail', 'Saisissez une adresse e-mail valide.'),
        findsOne,
        reason: 'errored once, the field is asked again as it changes',
      );
      await tester.enterText(input('Votre e-mail'), 'jean@salon.ci');
      await tester.pump();
      expect(find.text('Saisissez une adresse e-mail valide.'), findsNothing);
    });

    testWidgets('a code of four digits: said under the code, nothing sent', (
      tester,
    ) async {
      await toCodeStep(tester);
      await submitCode(tester, '1234');

      expect(
        under('Code à 6 chiffres', 'Le code doit comporter 6 chiffres.'),
        findsOne,
      );
      expect(auth.verifies, 0);
      expect(find.text('DASHBOARD'), findsNothing);
    });
  });

  group('the server\'s refusals', () {
    testWidgets('a wrong code is said under the code, not under the form; a '
        'new code typed clears it', (tester) async {
      await toCodeStep(tester);
      await submitCode(tester, '000000'); // the mock's code is 123456

      expect(auth.verifies, 1);
      expect(under('Code à 6 chiffres', 'Code incorrect.'), findsOne);
      expect(underTheForm('Code incorrect.'), findsNothing);
      expect(focused(tester, 'Code à 6 chiffres'), isTrue);

      await tester.enterText(input('Code à 6 chiffres'), '111111');
      await tester.pump();
      expect(find.text('Code incorrect.'), findsNothing);
    });

    testWidgets('`otp_expired`: its sentence under the code', (tester) async {
      auth.codeRefusal = (
        code: 'otp_expired',
        message: 'Code expiré. Demandez un nouveau code.',
      );
      await toCodeStep(tester);
      await submitCode(tester, '123456');

      expect(
        under('Code à 6 chiffres', 'Code expiré. Demandez un nouveau code.'),
        findsOne,
      );
    });

    testWidgets('a refusal that is no field\'s stays under the form', (
      tester,
    ) async {
      auth.codeRefusal = (
        code: 'account_suspended',
        message: 'Compte suspendu.',
      );
      await toCodeStep(tester);
      await submitCode(tester, '123456');

      expect(underTheForm('Compte suspendu.'), findsOne);
      expect(under('Code à 6 chiffres', 'Compte suspendu.'), findsNothing);
    });

    testWidgets('an address the server refuses is said under the e-mail', (
      tester,
    ) async {
      auth.sendRefusal = (code: 'invalid_email', message: 'E-mail invalide.');
      await tester.pumpWidget(app());
      await settle(tester);
      await sendFor(tester, 'jean@salon-excellence.test');

      expect(
        under('Votre e-mail', 'Saisissez une adresse e-mail valide.'),
        findsOne,
      );
      expect(find.text('E-mail invalide.'), findsNothing);
    });

    testWidgets('a new code: the last one\'s fault is gone', (tester) async {
      await toCodeStep(tester);
      await submitCode(tester, '000000');
      expect(under('Code à 6 chiffres', 'Code incorrect.'), findsOne);

      await tester.tap(find.text('Changer d’e-mail'));
      await settle(tester);
      await tester.tap(find.text('Continuer avec e-mail'));
      await settle(tester);

      expect(field('Code à 6 chiffres'), findsOne);
      expect(find.text('Code incorrect.'), findsNothing);
    });
  });
}

/// The mock, counting what reached it — and, while a refusal is set,
/// refusing that step under its code.
class _ScriptedAuth extends MockAuthService {
  ({String code, String message})? sendRefusal;
  ({String code, String message})? codeRefusal;
  int sends = 0;
  int verifies = 0;

  @override
  Future<ApiResponse<String>> requestProviderEmailOtp(String email) async {
    sends++;
    final refusing = sendRefusal;
    if (refusing != null) {
      return ApiResponse.error(refusing.message, code: refusing.code);
    }
    return super.requestProviderEmailOtp(email);
  }

  @override
  Future<ProviderLoginResult> verifyProviderEmailOtp(
    String email,
    String code,
  ) async {
    verifies++;
    final refusing = codeRefusal;
    if (refusing != null) {
      return ProviderLoginResult.failure(refusing.message, code: refusing.code);
    }
    return super.verifyProviderEmailOtp(email, code);
  }
}
