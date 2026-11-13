import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/screens/provider/onboarding/pro_onboarding_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_kyc_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// The mock world, with the two knobs this screen needs: a THIRD photo (the
/// seeded salon has two, and ≥3 is a publish gate — without it the button
/// stays disabled and no refusal can be reached) and a scripted publish
/// answer. `publishAnswer == null` runs the real mock publish.
class _ScenarioProService extends MockProService {
  ApiResponse<PublishOutcome>? publishAnswer;

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({SalonId? salonId}) async {
    final res = await super.getMyProvider(salonId: salonId);
    final data = res.data;
    if (data == null) return res;
    // `copyWith` keeps the read's validation as it came (B0.18).
    return ApiResponse.success(
      data.copyWith(
        salon: data.salon.copyWith(
          imageUrls: [...data.salon.imageUrls, 'asset:third.png'],
        ),
      ),
    );
  }

  @override
  Future<ApiResponse<PublishOutcome>> publishSalon(SalonId providerId) async =>
      publishAnswer ?? super.publishSalon(providerId);
}

/// « Configuration » — the go-live checklist (pro-salon-lifecycle B3) after
/// the companion path (docs/design/pro-companion-path.md §2.2): no offer
/// step, go-live without a choice, and a refused publish that states a fact
/// with NO action. Run on BOTH platforms where it matters — no platform
/// branch may exist, and `TargetPlatformVariant` is what proves it.
void main() {
  final pro = _ScenarioProService();
  final subs = MockSubscriptionService();
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.proArtistService = MockProArtistService();
    serviceLocator.proKycService = MockProKycService();
    serviceLocator.subscriptionService = subs;
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() {
    MockData.resetTeam();
    subs.resetForTests(); // SETUP: no offer row
    pro.publishAnswer = null;
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final auth = await signInPro(tester);
    // The sign-in's « Mes salons » load, landed in real time: a publish's
    // re-read waits for a load already out (B0.18 §6.2), and that one's
    // timer is not the test clock's.
    await tester.runAsync(auth.rereadMySalons);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProOnboardingProvider()),
        ],
        home: const ProOnboardingScreen(),
      ),
    );
    // services → staff → hours → deposit → listing → KYC: six mock calls.
    await settleMocks(tester, rounds: 7);
  }

  Future<void> goLive(WidgetTester tester) async {
    final button = find.text('Mettre mon profil en ligne');
    await tester.scrollUntilVisible(button, 200);
    await tester.tap(button);
    // The publish and its offer read; then, on a success, the session's two
    // re-reads (B0.18 §6.2: /me/provider and /me/salons, side by side) —
    // one more for the validation view's offer read on some fixtures.
    await settleMocks(tester, rounds: 4);
  }

  /// What the checklist and its feedback may never say or offer (§2.1).
  void expectNoOfferChoice() {
    for (final f in [
      find.textContaining('Choisissez votre offre'),
      find.textContaining('mois offerts'),
      find.text('Choisir'),
      find.byType(SnackBarAction),
    ]) {
      expect(f, findsNothing, reason: '$f');
    }
  }

  testWidgets('no offer step, and « Mettre mon profil en ligne » is enabled '
      'with every server gate met — no offer chosen', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Profil de l’entreprise'), findsOneWidget);
    // Walk the whole checklist: the offer step was the LAST row.
    final button = find.text('Mettre mon profil en ligne');
    await tester.scrollUntilVisible(button, 200);
    expectNoOfferChoice();
    expect(
      find.text(
        'Complétez les étapes essentielles pour mettre votre profil en ligne.',
      ),
      findsNothing,
      reason: 'the button is still gated on something the salon cannot do',
    );
    final enabled = tester
        .widget<ElevatedButton>(
          find.ancestor(of: button, matching: find.byType(ElevatedButton)),
        )
        .onPressed;
    expect(enabled, isNotNull);
  }, variant: bothPlatforms);

  testWidgets('a salon that never chose its deposit reads « Facultatif » on '
      '« Acompte & annulation » (B7.7, decision 24)', (tester) async {
    // The server's defaults for a salon that never saved: off, 0 %.
    final i = MockData.providers.indexWhere((p) => p.id == 'provider1');
    final original = MockData.providers[i];
    MockData.providers[i] = original.copyWith(depositPercentage: 0);
    addTearDown(() => MockData.providers[i] = original);
    await pumpScreen(tester);

    final step = find.text('Acompte & annulation');
    await tester.scrollUntilVisible(step, 200);
    expect(find.text('Facultatif'), findsOneWidget);
  });

  testWidgets('CONTROL — a saved choice (off, at the form\'s 30 %) reads no '
      '« Facultatif »', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Acompte & annulation'), 200);
    expect(find.text('Facultatif'), findsNothing);
  });

  // B0.18 (salon-go-live-approval §3.1, §3.6, §6.5): the publish is a
  // request — it starts no trial; MyWeli's validation starts the salon's one
  // trial. Replaces « the first publish goes live and the mock starts the
  // trial », watched red on the new mock first (the trial read null).
  testWidgets('a salon that never asked: the request records it as pending '
      'and starts no trial; MyWeli\'s validation starts the trial on Pro and '
      'takes the salon live (§3.1, §3.6)', (tester) async {
    MockData.seedNeverAsked(SalonId('provider1'));
    await pumpScreen(tester);
    await goLive(tester);

    expect(
      MockData.salonValidations[SalonId('provider1')]?.state,
      SalonValidationState.pending,
    );
    expect(MockData.salonStatuses[SalonId('provider1')], 'draft');
    late ApiResponse<SalonSubscription> offer;
    await tester.runAsync(() async {
      offer = await subs.getSalonSubscription(SalonId('provider1'));
    });
    expect(offer.code, 'no_offer', reason: 'a request starts no trial');

    // The admin validates.
    await tester.runAsync(() async {
      expect(
        (await pro.validateSalonForTests(SalonId('provider1'))).success,
        isTrue,
      );
      offer = await subs.getSalonSubscription(SalonId('provider1'));
    });
    expect(offer.data?.status, SalonOfferStatus.trial);
    expect(offer.data?.tier, SalonTier.pro);
    expect(MockData.salonStatuses[SalonId('provider1')], isNull);
    expect(MockData.salonValidations[SalonId('provider1')]?.wentLive, isTrue);
  }, variant: bothPlatforms);

  testWidgets('a publish refused by the offer gate (EXPIRED offer): the '
      'neutral sentence and NO action', (tester) async {
    // A stale sentence from the service: the screen must not echo it.
    pro.publishAnswer = ApiResponse.error(
      'Ancienne phrase du serveur.',
      code: 'offer_required',
    );
    await pumpScreen(tester);
    await goLive(tester);

    expect(
      find.text(
        'La mise en ligne est indisponible : l’offre de votre salon n’est '
        'plus active.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ancienne phrase du serveur.'), findsNothing);
    expectNoOfferChoice();
  }, variant: bothPlatforms);

  testWidgets('the demo account\'s lock reads as itself, not « Une erreur est '
      'survenue »', (tester) async {
    pro.publishAnswer = ApiResponse.error(
      'Compte de démonstration — cette action est désactivée.',
      code: 'demo_account_locked',
    );
    await pumpScreen(tester);
    await goLive(tester);

    expect(
      find.text('Compte de démonstration — cette action est désactivée.'),
      findsOneWidget,
    );
    expectNoOfferChoice();
  }, variant: bothPlatforms);
}
