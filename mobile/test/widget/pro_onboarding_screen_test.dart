import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
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
  ApiResponse<bool>? publishAnswer;

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    final res = await super.getMyProvider(salonId: salonId);
    final data = res.data;
    if (data == null) return res;
    return ApiResponse.success(
      MyProviderInfo(
        salon: data.salon.copyWith(
          imageUrls: [...data.salon.imageUrls, 'asset:third.png'],
        ),
        membership: data.membership,
      ),
    );
  }

  @override
  Future<ApiResponse<bool>> publishSalon(String providerId) async =>
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
    await settleMocks(tester, rounds: 2);
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

  testWidgets('the first publish goes live and the mock starts the trial — '
      'the server rule mirrored (§3.1)', (tester) async {
    await pumpScreen(tester);
    await goLive(tester);

    expect(find.text('🎉 Votre profil est en ligne !'), findsOneWidget);
    late ApiResponse<SalonSubscription> offer;
    await tester.runAsync(() async {
      offer = await subs.getSalonSubscription('provider1');
    });
    expect(offer.data?.status, SalonOfferStatus.trial);
    expect(offer.data?.tier, SalonTier.pro);
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
