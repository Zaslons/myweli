import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/screens/provider/settings/deposit_settings_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _MockProService extends Mock implements ProServiceInterface {}

void main() {
  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    // Multi-pays MP2: the operator chips read the country's catalog.
    serviceLocator.localityService = MockLocalityService();
  });

  late _MockProService service;

  setUpAll(() {
    service = _MockProService();
    serviceLocator.proService = service;
  });

  setUp(() => reset(service));

  Widget host() => wrapApp(
    providers: [
      ChangeNotifierProvider(create: (_) => ProDepositSettingsProvider()),
      // T52 lock reads the session's verification status.
      ChangeNotifierProvider(create: (_) => ProAuthProvider()),
      // Multi-pays MP2: the operator-catalog chips.
      ChangeNotifierProvider(create: (_) => LocalityProvider()),
    ],
    home: const DepositSettingsScreen(providerId: 'p1'),
  );

  /// Same host, on a settings provider the test already primed — the screen
  /// prefills its Mobile Money field from `provider.mobileMoneyNumber`, so this
  /// is how a test opens the screen on a salon that HAS a stored handle.
  Widget hostWith(ProDepositSettingsProvider settings) => wrapApp(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider(create: (_) => ProAuthProvider()),
      ChangeNotifierProvider(create: (_) => LocalityProvider()),
    ],
    home: const DepositSettingsScreen(providerId: 'p1'),
  );

  testWidgets('shows the loaded policy', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: true, depositPercentage: 0.30),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Exiger un acompte'), findsOneWidget);
    expect(find.text('30 %'), findsOneWidget);
    // T52: an unverified session sees the lock banner.
    expect(find.textContaining('après la vérification'), findsOneWidget);
    // The banner lengthens the lazy ListView — bring the tail into view.
    await tester.scrollUntilVisible(
      find.text('Enregistrer', skipOffstage: false),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enregistrer', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Recevoir l’acompte', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('hides the percentage when the deposit is off', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: false, depositPercentage: 0.30),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Pourcentage de l’acompte'), findsNothing);
    // Drain the mock locality fetch (pumpAndSettle never advances bare
    // timers — the R4b lesson).
    await tester.pump(const Duration(milliseconds: 400));
  });

  // ---------------------------------------------------------------------------
  // A7-fix — **the per-funnel gate §20 claims, made real for the MONEY path.**
  //
  // A7 (SYSTEM.md §14 / §21 row 19) shipped this screen's Mobile Money field as
  // a LOCKOUT: it validated the number as ten LOCAL digits while
  // `PUT /deposit-policy` requires **E.164** (openapi.yaml:1758). The two rules
  // have an EMPTY intersection, so with deposits on, NO salon could have saved a
  // deposit policy at all — on the one field that decides where a client's
  // deposit money lands. The screen now uses [Validators.phoneNumber] (E.164;
  // since phone-national-length.md, exactly 10 digits after +225) through a
  // [PhoneNumberField]; §20 claimed a per-funnel widget test held that, and no
  // such test existed.
  //
  // The shape below is the one §14 actually specifies, and the one every funnel
  // test in this repo should hold: **the press answers, under the field (rule 1)
  // · no `SnackBar` (rule 3) · nothing is saved · fixing the value clears the
  // message without a second submit (rule 2)** — plus, here, the other half a
  // lockout needs: the rule must ACCEPT what the server contract requires.
  // ---------------------------------------------------------------------------

  /// The stored handle, in the shape the API stores and returns: E.164.
  const storedNumber = '+2250707123456';

  const loadedPolicy = DepositPolicy(
    depositRequired: true,
    depositPercentage: 0.30,
    mobileMoneyOperator: 'wave',
    mobileMoneyNumber: storedNumber,
  );

  /// Advance past the mock latency without pumpAndSettle (the brand loader
  /// animates forever, so pumpAndSettle would never settle mid-load).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// The form is a lazy [ListView] taller than the test surface, so « the field »
  /// and « the button » are never on screen at once — the same helper the two
  /// tests above use, as a direction-aware wrapper.
  Future<void> scrollTo(
    WidgetTester tester,
    Finder target, {
    double delta = 200,
  }) => tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
  );

  final saveButton = find.text('Enregistrer', skipOffstage: false);
  final numberLabel = find.text('Numéro Mobile Money', skipOffstage: false);

  void stubSaveOk() {
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
        mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
        mobileMoneyNumber: any(named: 'mobileMoneyNumber'),
      ),
    ).thenAnswer((_) async => ApiResponse.success(loadedPolicy));
  }

  /// Every `updateDepositPolicy` call, whatever its arguments — the "did the
  /// press reach the network at all" question.
  VerificationResult saveCalls() => verify(
    () => service.updateDepositPolicy(
      any(),
      depositRequired: any(named: 'depositRequired'),
      depositPercentage: any(named: 'depositPercentage'),
      cancellationWindowHours: any(named: 'cancellationWindowHours'),
      mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
      mobileMoneyNumber: captureAny(named: 'mobileMoneyNumber'),
    ),
  );

  /// The field's own text input — inside [PhoneNumberField], which shows the
  /// NATIONAL part under the country's flag (+225 · « 0707123456 »).
  Finder numberInput() => find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.byType(TextField),
  );

  Finder underTheNumber(String message) => find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.text(message),
  );

  const tenDigits = 'Le numéro doit comporter 10 chiffres après +225.';

  VerificationResult noSave() => verifyNever(
    () => service.updateDepositPolicy(
      any(),
      depositRequired: any(named: 'depositRequired'),
      depositPercentage: any(named: 'depositPercentage'),
      cancellationWindowHours: any(named: 'cancellationWindowHours'),
      mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
      mobileMoneyNumber: any(named: 'mobileMoneyNumber'),
    ),
  );

  testWidgets('A7 LOCKOUT: « Enregistrer » accepts the stored E.164 number the '
      'screen just loaded', (tester) async {
    when(
      () => service.getDepositPolicy(any()),
    ).thenAnswer((_) async => ApiResponse.success(loadedPolicy));
    stubSaveOk();

    // Open on a provider that already holds the stored policy, so the field is
    // prefilled from it — the app's own round trip: what the API returned goes
    // back to the API untouched. (The cold-start twin is the next test.)
    final settings = ProDepositSettingsProvider();
    await settings.load('p1');
    await tester.pumpWidget(hostWith(settings));
    await settle(tester);
    await settle(tester);

    await scrollTo(tester, numberLabel);
    expect(
      tester.widget<TextField>(numberInput()).controller?.text,
      '0707123456',
      reason:
          'the field carries the stored handle — its national part, under '
          '+225 — and this is what gets judged',
    );

    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await settle(tester);
    await settle(tester);

    // THE lockout assertion: the client rule must accept exactly what the
    // server contract requires. A 10-digit-local rule rejects every E.164
    // value, so the save below never happened and this salon could never
    // store a deposit policy.
    final sent = saveCalls().captured.single;
    expect(
      sent,
      storedNumber,
      reason: 'the E.164 handle reaches PUT /deposit-policy unchanged',
    );
    expect(
      find.text('Paramètres enregistrés'),
      findsOneWidget,
      reason: 'and the salon is told it saved',
    );

    await scrollTo(tester, numberLabel, delta: -200);
    expect(
      find.text('Saisissez un numéro de téléphone valide.'),
      findsNothing,
      reason: 'the app must be able to save what it just loaded',
    );
  });

  /// **Cold-start prefill** — reported here as broken by the A7-fix slice and
  /// left uncovered: `_buildForm` burned a `_numberPrefilled` flag on the very
  /// first build, BEFORE `load()` had even been called, so the stored handle
  /// never reached the controller. A first visit after launch pressed
  /// « Enregistrer » into « Saisissez un numéro de téléphone. » — and before
  /// A7's validator existed, the same press sent `null` and WIPED the stored
  /// handle. The number is now the stored one until the salon edits it, and
  /// the field is built from it when the form first shows it.
  testWidgets('cold start: the stored number is in the field, and it is what '
      'saves', (tester) async {
    when(
      () => service.getDepositPolicy(any()),
    ).thenAnswer((_) async => ApiResponse.success(loadedPolicy));
    stubSaveOk();

    await tester.pumpWidget(host());
    await settle(tester);
    await settle(tester);

    await scrollTo(tester, numberLabel);
    expect(
      tester.widget<TextField>(numberInput()).controller?.text,
      '0707123456',
    );

    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await settle(tester);
    await settle(tester);

    expect(saveCalls().captured.single, storedNumber);
  });

  testWidgets(
    'an invalid Mobile Money number answers UNDER THE FIELD, with no bar, '
    'and saves nothing',
    (tester) async {
      when(
        () => service.getDepositPolicy(any()),
      ).thenAnswer((_) async => ApiResponse.success(loadedPolicy));
      stubSaveOk();

      await tester.pumpWidget(host());
      await settle(tester);
      await settle(tester);

      // `"abc"` is the literal value A7's review found saving fine, rendering
      // verbatim in the client's deposit sheet and going into the Wave deep
      // link — the whole path's only transformation was `.trim()`.
      await scrollTo(tester, numberLabel);
      await tester.enterText(numberInput(), 'abc');
      await tester.pump();

      // Rule 5 keeps the button live, so the press MUST answer rather than
      // silently succeed.
      await scrollTo(tester, saveButton);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Enregistrer'),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: '§14 rule 5: never disabled to express "invalid"',
      );

      await tester.tap(saveButton);
      await settle(tester);
      await settle(tester);

      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar',
      );
      noSave();

      // The message lives in the field's own decoration, so it is built exactly
      // when the field is. Under +225, what to do is « 10 chiffres ».
      await scrollTo(tester, numberLabel, delta: -200);
      expect(
        underTheNumber(tenDigits),
        findsOneWidget,
        reason: 'the fault renders under the field it belongs to (§14 rule 1)',
      );

      // Rule 2: fixing it clears the message without another submit.
      await tester.enterText(numberInput(), '0707123456');
      await tester.pump();
      expect(
        find.text(tenDigits),
        findsNothing,
        reason: '§14 rule 2 — a fixed field clears itself, no second press',
      );
    },
  );

  testWidgets(
    'deposits OFF and no number: nothing to judge — a salon that takes no '
    'deposit still saves',
    (tester) async {
      when(() => service.getDepositPolicy(any())).thenAnswer(
        (_) async => ApiResponse.success(
          const DepositPolicy(depositRequired: false, depositPercentage: 0.30),
        ),
      );
      stubSaveOk();

      await tester.pumpWidget(host());
      await settle(tester);
      await settle(tester);

      expect(
        numberLabel,
        findsNothing,
        reason: 'the field only shows when a deposit is actually collected',
      );

      await scrollTo(tester, saveButton);
      await tester.tap(saveButton);
      await settle(tester);
      await settle(tester);

      // With deposits off the number is OPTIONAL: an empty one must not stop
      // the press.
      expect(
        find.text('Saisissez un numéro de téléphone.'),
        findsNothing,
        reason: 'an absent number is not a fault when no deposit is collected',
      );
      expect(
        find.text('Paramètres enregistrés'),
        findsOneWidget,
        reason: 'the policy saved',
      );
      final sent = saveCalls().captured.single;
      expect(
        sent,
        isNull,
        reason: 'and no Mobile Money handle is invented on the way out',
      );
    },
  );

  /// phone-national-length.md §2.3 — **deposits OFF does not mean unchecked.**
  /// The number is sent whatever the switch says (PUT replaces the whole
  /// policy), and the server checks any non-null one; the app skipped its own
  /// check when deposits were off, so a stored short number came back from
  /// the server as the form-level « Informations invalides. », with nothing
  /// under any field — on a screen where that field was not even shown.
  testWidgets('deposits OFF + a short stored number: the field shows, with '
      'the message under it, and nothing is saved', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(
          depositRequired: false,
          depositPercentage: 0.30,
          mobileMoneyOperator: 'wave',
          mobileMoneyNumber: '+2250707123',
        ),
      ),
    );
    stubSaveOk();

    await tester.pumpWidget(host());
    await settle(tester);
    await settle(tester);

    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await settle(tester);
    await settle(tester);

    noSave();
    expect(find.byType(SnackBar), findsNothing);
    await scrollTo(tester, numberLabel, delta: -200);
    expect(
      underTheNumber(tenDigits),
      findsOneWidget,
      reason: 'judged whenever it is not empty — and shown, so it can be fixed',
    );

    // Fixed in place, the message goes (rule 2) and the field STAYS — it does
    // not vanish under the salon's thumb the moment the number turns valid.
    await tester.enterText(numberInput(), '0707123456');
    await tester.pump();
    expect(find.text(tenDigits), findsNothing);
    expect(numberLabel, findsOneWidget);

    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await settle(tester);
    await settle(tester);
    expect(saveCalls().captured.single, storedNumber);

    // The card did its job. Deposits are still OFF, so once the fix is saved
    // it goes — one saved policy, one layout (the review of this branch: it
    // stayed, saying clients pay to this number while no deposit is asked).
    expect(numberLabel, findsNothing);
    expect(find.text('Recevoir l’acompte', skipOffstage: false), findsNothing);
  });

  // ---- phone-leftovers.md §2: the server's verdict, under the field -------
  //
  // `PUT /deposit-policy` refused the number as `invalid_input`, the code of
  // every other field too, and the screen printed « Informations invalides. »
  // in a bar. It answers `invalid_phone` now — the number's own fault.

  const refusedNumber = 'Saisissez un numéro de téléphone valide.';

  /// The save refused by the server under `invalid_phone`, with the message
  /// `ApiProService._messageFor` gives it.
  void refuseNumber() {
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
        mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
        mobileMoneyNumber: any(named: 'mobileMoneyNumber'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.error(
        'Numéro invalide (format international, ex. +2250700000000).',
        code: 'invalid_phone',
      ),
    );
  }

  /// « Enregistrer », pressed for real. `scrollUntilVisible` ends on a jump
  /// that is laid out only at the next frame, so on the long form (deposits
  /// on) a tap straight after it lands where the button WAS — off screen, and
  /// nothing is sent. The pump in between is what makes the press reach the
  /// save, and the tests below check that it did.
  Future<void> pressSave(WidgetTester tester) async {
    await scrollTo(tester, saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await settle(tester);
    await settle(tester);
  }

  testWidgets('the server\'s `invalid_phone` lands UNDER the Mobile Money '
      'field, not in a bar', (tester) async {
    when(
      () => service.getDepositPolicy(any()),
    ).thenAnswer((_) async => ApiResponse.success(loadedPolicy));
    refuseNumber();

    await tester.pumpWidget(host());
    await settle(tester);
    await settle(tester);

    await pressSave(tester);

    expect(
      saveCalls().captured.single,
      storedNumber,
      reason: 'the client rule passed it: the SERVER refused it',
    );
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '§14 rule 3 — the refused number is a field fault, not a bar',
    );
    await scrollTo(tester, numberLabel, delta: -200);
    expect(
      underTheNumber(refusedNumber),
      findsOneWidget,
      reason: '§14 rule 1 — under the field the server refused',
    );

    // Rule 2: a changed number that passes the client rule clears it.
    await tester.enterText(numberInput(), '0707123457');
    await tester.pump();
    expect(find.text(refusedNumber), findsNothing);
  });

  testWidgets('deposits OFF: a number the server refuses reveals the hidden '
      'card, with the message under the field', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(
          depositRequired: false,
          depositPercentage: 0.30,
          mobileMoneyOperator: 'wave',
          mobileMoneyNumber: storedNumber,
        ),
      ),
    );
    refuseNumber();

    await tester.pumpWidget(host());
    await settle(tester);
    await settle(tester);
    expect(
      numberLabel,
      findsNothing,
      reason: 'deposits off: the card is hidden',
    );

    await pressSave(tester);

    expect(saveCalls().captured.single, storedNumber);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      numberLabel,
      findsOneWidget,
      reason: 'the message needs a field to sit under — the card shows',
    );
    await scrollTo(tester, numberLabel, delta: -200);
    expect(underTheNumber(refusedNumber), findsOneWidget);
  });

  testWidgets('any other refusal is still the bar it was', (tester) async {
    when(
      () => service.getDepositPolicy(any()),
    ).thenAnswer((_) async => ApiResponse.success(loadedPolicy));
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
        mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
        mobileMoneyNumber: any(named: 'mobileMoneyNumber'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.error(
        'Action non autorisée pour ce salon.',
        code: 'forbidden',
      ),
    );

    await tester.pumpWidget(host());
    await settle(tester);
    await settle(tester);

    await pressSave(tester);

    expect(saveCalls().captured.single, storedNumber);
    expect(
      find.widgetWithText(SnackBar, 'Action non autorisée pour ce salon.'),
      findsOneWidget,
    );
    await scrollTo(tester, numberLabel, delta: -200);
    expect(find.text(refusedNumber), findsNothing);
  });

  testWidgets('deposits OFF: switching deposits on then off again hides the '
      'revealed card', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(
          depositRequired: false,
          depositPercentage: 0.30,
          mobileMoneyOperator: 'wave',
          mobileMoneyNumber: '+2250707123',
        ),
      ),
    );
    stubSaveOk();

    // A verified session — the switch is locked otherwise (T52).
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => ProDepositSettingsProvider()),
          ChangeNotifierProvider<ProAuthProvider>(
            create: (_) => _VerifiedPro(),
          ),
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        home: const DepositSettingsScreen(providerId: 'p1'),
      ),
    );
    await settle(tester);
    await settle(tester);

    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await settle(tester);
    noSave();
    expect(numberLabel, findsOneWidget, reason: 'revealed by the refused save');

    final toggle = find.byType(SwitchListTile, skipOffstage: false);
    await scrollTo(tester, toggle, delta: -200);
    await tester.tap(toggle); // on: the card is the deposit's own
    await settle(tester);
    expect(numberLabel, findsOneWidget);
    await tester.tap(toggle); // off again: hidden, as on any visit
    await settle(tester);
    expect(numberLabel, findsNothing);
  });
}

/// A session whose salon is verified, so « Exiger un acompte » can be toggled.
class _VerifiedPro extends ProAuthProvider {
  @override
  ProviderUser? get provider => ProviderUser(
    id: 'p1',
    phoneNumber: '+2250707123456',
    businessName: 'Salon',
    businessType: BusinessType.salon,
    verificationStatus: VerificationStatus.verified,
    createdAt: DateTime(2026),
  );
}
