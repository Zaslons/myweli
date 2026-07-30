import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/screens/provider/settings/deposit_settings_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
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
    expect(
      find.textContaining('après la vérification'),
      findsOneWidget,
    );
    // The banner lengthens the lazy ListView — bring the tail into view.
    await tester.scrollUntilVisible(
      find.text('Enregistrer', skipOffstage: false),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enregistrer', skipOffstage: false), findsOneWidget);
    expect(
        find.text('Recevoir l’acompte', skipOffstage: false), findsOneWidget);
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
  // deposit money lands. The screen now uses [Validators.phoneNumber] (E.164);
  // §20 claimed a per-funnel widget test held that, and no such test existed.
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
  Future<void> scrollTo(WidgetTester tester, Finder target,
          {double delta = 200}) =>
      tester.scrollUntilVisible(
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

  testWidgets(
      'A7 LOCKOUT: « Enregistrer » accepts the stored E.164 number the '
      'screen just loaded', (tester) async {
    when(() => service.getDepositPolicy(any()))
        .thenAnswer((_) async => ApiResponse.success(loadedPolicy));
    stubSaveOk();

    // Open on a provider that already holds the stored policy, so the field is
    // prefilled from it — the app's own round trip: what the API returned goes
    // back to the API untouched. (Cold-start prefill is broken for an unrelated
    // reason; see the note at the end of this file.)
    final settings = ProDepositSettingsProvider();
    await settings.load('p1');
    await tester.pumpWidget(hostWith(settings));
    await settle(tester);
    await settle(tester);

    await scrollTo(tester, numberLabel);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      storedNumber,
      reason: 'the field carries the stored handle — this is what gets judged',
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
    expect(sent, storedNumber,
        reason: 'the E.164 handle reaches PUT /deposit-policy unchanged');
    expect(find.text('Paramètres enregistrés'), findsOneWidget,
        reason: 'and the salon is told it saved');

    await scrollTo(tester, numberLabel, delta: -200);
    expect(find.text('Saisissez un numéro de téléphone valide.'), findsNothing,
        reason: 'the app must be able to save what it just loaded');
  });

  testWidgets(
      'an invalid Mobile Money number answers UNDER THE FIELD, with no bar, '
      'and saves nothing', (tester) async {
    when(() => service.getDepositPolicy(any()))
        .thenAnswer((_) async => ApiResponse.success(loadedPolicy));
    stubSaveOk();

    await tester.pumpWidget(host());
    await settle(tester);
    await settle(tester);

    // `"abc"` is the literal value A7's review found saving fine, rendering
    // verbatim in the client's deposit sheet and going into the Wave deep
    // link — the whole path's only transformation was `.trim()`.
    await scrollTo(tester, numberLabel);
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.pump();

    // Rule 5 keeps the button live, so the press MUST answer rather than
    // silently succeed.
    await scrollTo(tester, saveButton);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Enregistrer'),
    );
    expect(button.onPressed, isNotNull,
        reason: '§14 rule 5: never disabled to express "invalid"');

    await tester.tap(saveButton);
    await settle(tester);
    await settle(tester);

    expect(find.byType(SnackBar), findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar');
    verifyNever(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
        mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
        mobileMoneyNumber: any(named: 'mobileMoneyNumber'),
      ),
    );

    // The message lives in the field's own decoration, so it is built exactly
    // when the field is.
    await scrollTo(tester, numberLabel, delta: -200);
    expect(
        find.text('Saisissez un numéro de téléphone valide.'), findsOneWidget,
        reason: 'the fault renders under the field it belongs to (§14 rule 1)');

    // Rule 2: fixing it clears the message without another submit.
    await tester.enterText(find.byType(TextField).first, storedNumber);
    await tester.pump();
    expect(find.text('Saisissez un numéro de téléphone valide.'), findsNothing,
        reason: '§14 rule 2 — a fixed field clears itself, no second press');
  });

  testWidgets(
      'deposits OFF: the number is not judged at all — a salon that takes '
      'no deposit still saves', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: false, depositPercentage: 0.30),
      ),
    );
    stubSaveOk();

    await tester.pumpWidget(host());
    await settle(tester);
    await settle(tester);

    expect(numberLabel, findsNothing,
        reason: 'the field only exists when a deposit is actually collected');

    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await settle(tester);
    await settle(tester);

    // `_save` guards the rule with `if (provider.depositRequired)`: with
    // deposits off there is no number to require, so an empty one must not
    // stop the press.
    expect(find.text('Saisissez un numéro de téléphone.'), findsNothing,
        reason: 'an absent number is not a fault when no deposit is collected');
    expect(find.text('Paramètres enregistrés'), findsOneWidget,
        reason: 'the policy saved');
    final sent = saveCalls().captured.single;
    expect(sent, isNull,
        reason: 'and no Mobile Money handle is invented on the way out');
  });

  // NOT COVERED, because it is currently broken — reported, not asserted:
  // **cold-start prefill.** `_buildForm` guards the prefill with
  // `_numberPrefilled`, but the very first build runs BEFORE `load()` is even
  // called (`_isLoading` starts `false`, and the load is scheduled in a
  // post-frame callback), so the flag burns on an empty provider and the stored
  // handle never reaches the controller. Probed on this screen: a policy loaded
  // with `mobileMoneyNumber: '+2250707123456'` leaves the field at `''`. On a
  // first visit after launch a salon therefore presses « Enregistrer » and is
  // told « Saisissez un numéro de téléphone. » — the same lockout A7 shipped,
  // by a different route — and before A7's validator existed the same press
  // sent `mobileMoneyNumber: null` and WIPED the stored handle. Fixing it is
  // outside this test slice; the test above opens on an already-loaded provider
  // (the warm path, i.e. every visit after the first) so that it pins the E.164
  // contract rather than this bug.
}
