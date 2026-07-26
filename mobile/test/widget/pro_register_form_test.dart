import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_register_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// A7 — « an error belongs to its field, not to a toast » (SYSTEM.md §14,
/// §21 row 19), held for the **pro registration funnel**
/// (`lib/screens/provider/auth/pro_register_screen.dart`).
///
/// §20 claimed the A7 funnels were "held per funnel by widget tests"; this
/// funnel had none, and it shipped THREE of A7's six defects. Each test below
/// closes one of them:
///
///  1. `'email'` was declared as a rule in the `FieldErrors` map, bound to the
///     field's `errorText`, wired to `revalidate` — and **never validated**.
///     « Recevoir un code » fired on anything, including `pas-un-email`.
///     Closed by `_sendCodeChecked`.
///  2. `'code'` likewise: « S'inscrire » fired on anything, and the gate A7
///     deleted had been `length < 4` on a field labelled « Code à 6 chiffres »
///     with `maxLength: 6` — a four-digit code walked straight through.
///     Closed by `_handleEmailRegisterChecked` + `Validators.otp`.
///  3. the « Type d'entreprise » fault WAS computed and DID block the submit,
///     but rendered nowhere: the dropdown had no `errorText`. A7 had also
///     removed the disabled-button gate (§14 rule 5), so the press was live —
///     and did literally nothing. Closed by
///     `errorText: _errors['businessType']` on the `DropdownButtonFormField`.
///
/// Every test asserts the same shape §14 specifies: **the press answers, under
/// the field it belongs to (rule 1) · no `SnackBar` (rule 3) · the funnel does
/// not advance and nothing is registered · fixing the value clears the message
/// without a second submit (rule 2)**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    // `_login` → `refreshMembership()` → GET /me/provider on the happy path.
    serviceLocator.proService = MockProService();
  });

  setUp(() async {
    // `_createProvider` appends to the shared mock list; a leftover account
    // would answer the next register with `provider_exists`.
    MockData.providerUsers.removeWhere((p) => p.email == _email);
    await serviceLocator.authService.logoutProvider();
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/pro/register',
      routes: [
        GoRoute(
          path: '/pro/register',
          builder: (_, __) => const ProRegisterScreen(),
        ),
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, __) => const Scaffold(body: Text('DASHBOARD')),
        ),
      ],
    );
    return wrapApp(
      providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
      routerConfig: router,
    );
  }

  /// Advance past the mock latency without `pumpAndSettle` (the brand loader
  /// animates forever, so `pumpAndSettle` would never settle mid-load).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// The funnel is one tall form (business block + identity block). Give it a
  /// viewport that fits the whole thing so every submit is genuinely tappable
  /// — a `tap` that missed would prove nothing about the gate.
  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Créez votre compte professionnel'), findsOneWidget);
  }

  Finder fieldLabelled(String label) => find.widgetWithText(TextField, label);

  Future<void> type(WidgetTester tester, String label, String value) async {
    await tester.enterText(fieldLabelled(label), value);
    await tester.pump();
  }

  /// Pick a « Type d'entreprise » from the real dropdown menu.
  Future<void> pickBusinessType(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButton<BusinessType>));
    await settle(tester);
    // The button itself keeps every item mounted in an IndexedStack, so the
    // menu's copy is the LAST match.
    await tester.tap(find.text('Salon de beauté').last);
    await settle(tester);
  }

  /// Everything the business block needs, valid — so that in the identity
  /// tests the e-mail / code is the ONLY thing that can fail.
  Future<void> fillBusinessBlock(
    WidgetTester tester, {
    bool withType = true,
  }) async {
    await type(tester, 'Nom de l\'entreprise', 'Salon Awa');
    if (withType) await pickBusinessType(tester);
    await type(tester, 'Téléphone du salon', '0701020304');
    await type(tester, 'Adresse', 'Cocody, Abidjan');
  }

  // ---- Defect 3: the fault that rendered NOWHERE ---------------------------

  testWidgets(
      'the empty « Type d\'entreprise » answers UNDER the dropdown — the '
      'press that used to do literally nothing', (tester) async {
    await openForm(tester);
    await fillBusinessBlock(tester, withType: false);
    await type(tester, 'Votre e-mail', 'awa@salon.test');

    await tester.tap(find.text('Recevoir un code'));
    await settle(tester);

    expect(
      find.descendant(
        of: find.byType(DropdownButtonFormField<BusinessType>),
        matching: find.text('Indiquez le type d\'entreprise.'),
      ),
      findsOneWidget,
      reason: 'rule 1 — the fault renders under the field it belongs to; '
          'before the fix it was computed, blocked the submit, and was '
          'shown nowhere at all',
    );
    expect(find.byType(SnackBar), findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar');
    expect(find.text('Code à 6 chiffres'), findsNothing,
        reason: 'the funnel must not advance to the code step');
    expect(find.text('DASHBOARD'), findsNothing);

    // Rule 2: picking a type clears the message without a second submit.
    await pickBusinessType(tester);
    expect(find.text('Indiquez le type d\'entreprise.'), findsNothing);
  });

  // ---- Defect 1: `email` declared, never validated -------------------------

  testWidgets(
      'an invalid e-mail answers under the e-mail field — « Recevoir un '
      'code » no longer fires on anything', (tester) async {
    await openForm(tester);
    await fillBusinessBlock(tester);
    await type(tester, 'Votre e-mail', 'pas-un-email');

    await tester.tap(find.text('Recevoir un code'));
    await settle(tester);

    expect(
      find.descendant(
        of: fieldLabelled('Votre e-mail'),
        matching: find.text('Saisissez une adresse e-mail valide.'),
      ),
      findsOneWidget,
      reason: 'rule 1 — the message belongs under the e-mail field',
    );
    expect(find.byType(SnackBar), findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar');
    expect(
      find.text('Code à 6 chiffres'),
      findsNothing,
      reason: 'no code was requested, so the code step must not open',
    );
    expect(find.textContaining('Code (dev)'), findsNothing,
        reason: 'the dev code only exists once requestEmailOtp has run');

    // Rule 2: fixing it clears the message without another submit.
    await type(tester, 'Votre e-mail', _email);
    expect(find.text('Saisissez une adresse e-mail valide.'), findsNothing);
  });

  testWidgets('an EMPTY e-mail gets the required message, not silence',
      (tester) async {
    await openForm(tester);
    await fillBusinessBlock(tester);

    await tester.tap(find.text('Recevoir un code'));
    await settle(tester);

    expect(
      find.descendant(
        of: fieldLabelled('Votre e-mail'),
        matching: find.text('Saisissez une adresse e-mail.'),
      ),
      findsOneWidget,
      reason: 'rule 5 makes the button live, so an empty submit MUST answer',
    );
    expect(find.byType(SnackBar), findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar');
    expect(find.text('Code à 6 chiffres'), findsNothing);
  });

  // ---- Defect 2: `code` declared, never validated; the 4-digit hole --------

  /// Reach the code step the way a real salon does.
  Future<void> reachCodeStep(WidgetTester tester) async {
    await openForm(tester);
    await fillBusinessBlock(tester);
    await type(tester, 'Votre e-mail', _email);

    await tester.tap(find.text('Recevoir un code'));
    await settle(tester);
    expect(find.text('Code à 6 chiffres'), findsOneWidget,
        reason: 'a fully valid business block + e-mail must NOT be blocked — '
            'the gates answer faults, they do not stonewall a good form');
  }

  testWidgets(
      'a FOUR-digit code is refused under the code field — the hole the '
      'old « length < 4 » gate left open', (tester) async {
    await reachCodeStep(tester);

    await type(tester, 'Code à 6 chiffres', '1234');
    await tester.tap(find.text('S\'inscrire'));
    await settle(tester);

    expect(
      find.descendant(
        of: fieldLabelled('Code à 6 chiffres'),
        matching: find.text('Le code doit comporter 6 chiffres.'),
      ),
      findsOneWidget,
      reason: 'rule 1 — under the code field; the label, the maxLength and '
          'the backend all said six while the gate said four',
    );
    expect(find.byType(SnackBar), findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar');
    expect(find.text('DASHBOARD'), findsNothing,
        reason: 'and above all the registration must not go through');
    expect(
      MockData.providerUsers.any((p) => p.email == _email),
      isFalse,
      reason: 'nothing was saved — no salon account exists',
    );

    // Rule 2: completing the code clears the message without another submit.
    await type(tester, 'Code à 6 chiffres', MockAuthService.demoOtp);
    expect(find.text('Le code doit comporter 6 chiffres.'), findsNothing);
  });

  testWidgets('an EMPTY code answers instead of registering', (tester) async {
    await reachCodeStep(tester);

    await tester.tap(find.text('S\'inscrire'));
    await settle(tester);

    expect(
      find.descendant(
        of: fieldLabelled('Code à 6 chiffres'),
        matching: find.text('Saisissez le code reçu.'),
      ),
      findsOneWidget,
      reason: 'rule 5 makes the button live, so an empty submit MUST answer',
    );
    expect(find.byType(SnackBar), findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar');
    expect(find.text('DASHBOARD'), findsNothing);
    expect(MockData.providerUsers.any((p) => p.email == _email), isFalse);
  });

  // ---- The gates must not stonewall a correct form -------------------------

  testWidgets(
      'the complete, valid funnel still registers and lands on the '
      'dashboard', (tester) async {
    await reachCodeStep(tester);

    await type(tester, 'Code à 6 chiffres', MockAuthService.demoOtp);
    await tester.tap(find.text('S\'inscrire'));
    await settle(tester);
    await settle(tester);

    expect(
      find.text('DASHBOARD'),
      findsOneWidget,
      reason: 'the A7 gates answer faults — they must not block a form '
          'that is actually valid',
    );
    expect(MockData.providerUsers.any((p) => p.email == _email), isTrue);
  });
}

/// The e-mail the funnel registers with — kept out of `MockData`'s seeds.
const _email = 'awa@salon.test';
