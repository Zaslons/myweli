import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/apple_logo.dart';
import 'package:myweli/widgets/common/google_g_logo.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// Auth overhaul P3 (docs/design/app-auth-social.md): the LoginScreen flow —
/// options → email code → MANDATORY contact phone → returnTo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `authService` is a `late final` — one instance for the file. The spy IS
  // the mock unless a test arms it (see the 10-digit group below).
  final spy = _SpyAuthService();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = spy;
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

  testWidgets('options step: Google + email visible, Apple hidden (Android)', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Continuer avec Google'), findsOneWidget);
    // Google's branding guidelines: the official « G » sits on the button.
    expect(find.byType(GoogleGLogo), findsOneWidget);
    expect(find.text('Continuer avec e-mail'), findsOneWidget);
    // Hidden because `_showApple` also requires iOS, and `flutter test`
    // reports android. NOT because the flag is off — it now defaults to true.
    expect(find.text('Continuer avec Apple'), findsNothing);
  });

  testWidgets('options step on iOS: Apple appears, as one family with Google', (
    tester,
  ) async {
    // Without this override the Apple button is unreachable from any test:
    // `flutter test` hard-wires `defaultTargetPlatform` to android, so
    // `_showApple` was false in every run and NOTHING has ever rendered it —
    // including the goldens. The rule-4.8 button shipped unseen.
    //
    // Reset in a `finally`, not `addTearDown`: the framework verifies the
    // foundation debug vars at the END OF THE BODY, before tearDowns run, and
    // fails the test for leaving one set.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('Continuer avec Apple'), findsOneWidget);
      // The mark that was missing entirely until now.
      expect(find.byType(AppleLogo), findsOneWidget);

      // The point of the slice: both buttons are the same control, differing
      // only in fill. Same height, same width, same shape — so a difference in
      // padding or type can never quietly return.
      final google = tester.getRect(
        find.ancestor(
          of: find.text('Continuer avec Google'),
          matching: find.byType(AppButton),
        ),
      );
      final apple = tester.getRect(
        find.ancestor(
          of: find.text('Continuer avec Apple'),
          matching: find.byType(AppButton),
        ),
      );
      expect(apple.size, google.size);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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

  /// docs/design/phone-national-length.md — **seen on the simulator on
  /// 2026-10-15**: this step accepted `+2250700000`, seven digits after +225,
  /// and saved it as the contact number every salon would dial.
  group('a +225 number has exactly 10 digits', () {
    // Armed to refuse for the whole group: a number that leaks through is
    // recorded but never STORED, so the Google account still has no phone in
    // the next test, and each test fails for its own reason only.
    setUp(() {
      spy.phonesSent.clear();
      spy.rejectPhoneWith = 'invalid_phone';
    });
    tearDown(() => spy.rejectPhoneWith = null);

    /// Sign in through Google and stop at the phone step.
    Future<void> toPhoneStep(WidgetTester tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(find.text('Votre numéro de téléphone'), findsOneWidget);
    }

    Finder underThePhone(String message) => find.descendant(
      of: find.byType(PhoneNumberField),
      matching: find.text(message),
    );

    testWidgets('seven digits answer under the field — and nothing is sent', (
      tester,
    ) async {
      await toPhoneStep(tester);

      await tester.enterText(find.byType(TextField).first, '0700000');
      await tester.pump();
      await tester.tap(find.text('Continuer'));
      await settle(tester);
      await settle(tester);

      expect(
        underThePhone('Le numéro doit comporter 10 chiffres après +225.'),
        findsOneWidget,
        reason: '§14 rule 1 + rule 4: under the field, saying what to do',
      );
      expect(
        spy.phonesSent,
        isEmpty,
        reason: 'no PATCH /me — the short number never leaves the phone',
      );
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('a server `invalid_phone` lands under the field, not as '
        '« Numéro ou code invalide. »', (tester) async {
      // The server is the authority (BACKEND.md §3.4): a number the client
      // let through can still be refused. That refusal used to render in the
      // form-level slot as « Numéro ou code invalide. » — on a screen with no
      // code on it.
      await toPhoneStep(tester);

      await tester.enterText(find.byType(TextField).first, '0700000001');
      await tester.pump();
      await tester.tap(find.text('Continuer'));
      await settle(tester);
      await settle(tester);

      expect(spy.phonesSent, ['+2250700000001']);
      expect(
        underThePhone('Saisissez un numéro de téléphone valide.'),
        findsOneWidget,
        reason: 'the server\'s verdict on the number belongs to the number',
      );
      expect(find.text('Numéro ou code invalide.'), findsNothing);
      expect(find.text('HOME'), findsNothing);
    });
  });
}

/// The mock, recording every `updateUser` phone — and optionally refusing it
/// the way `PATCH /me` does (400 `invalid_phone`, mapped by `ApiAuthService`).
class _SpyAuthService extends MockAuthService {
  String? rejectPhoneWith;
  final phonesSent = <String?>[];

  @override
  Future<ApiResponse<User>> updateUser({
    String? name,
    String? email,
    String? avatarUrl,
    String? phone,
  }) async {
    phonesSent.add(phone);
    if (rejectPhoneWith != null) {
      return ApiResponse.error(
        'Numéro ou code invalide.',
        code: rejectPhoneWith,
      );
    }
    return super.updateUser(
      name: name,
      email: email,
      avatarUrl: avatarUrl,
      phone: phone,
    );
  }
}
