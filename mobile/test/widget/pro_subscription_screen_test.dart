import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/screens/provider/subscription/pro_subscription_screen.dart';
import 'package:myweli/services/interfaces/subscription_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SwitchableAuth extends MockAuthService {
  ProviderUser? current;

  @override
  Future<ProviderUser?> getCurrentProvider() async => current;
}

/// Scenario-switchable offer state (each test picks its inner service).
class _SwitchableSubs implements SubscriptionServiceInterface {
  SubscriptionServiceInterface inner = MockSubscriptionService();

  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  ) =>
      inner.getSalonSubscription(providerId);

  @override
  Future<ApiResponse<SalonSubscription>> chooseOffer(
    String providerId,
    SalonTier tier,
  ) =>
      inner.chooseOffer(providerId, tier);
}

/// Team access R3 §2.4 — « Mon abonnement »: the setup picker, the offer
/// cards (anchor prices, seats, 3 mois offerts), the four billing states,
/// trial_used and the owner-only guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = _SwitchableAuth();
  final subs = _SwitchableSubs();

  SalonSubscription state({
    SalonOfferStatus status = SalonOfferStatus.trial,
    bool unpublished = false,
  }) =>
      SalonSubscription(
        tier: SalonTier.pro,
        status: status,
        trialEndsAt: DateTime.now().add(const Duration(days: 45)),
        graceEndsAt: DateTime.now().add(const Duration(days: 52)),
        unpublishedForBilling: unpublished,
        seats: const SalonSeats(cap: 5, used: 3),
      );

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.subscriptionService = subs;
  });

  setUp(() {
    auth.current = MockData.providerUsers.first;
    subs.inner = MockSubscriptionService(); // setup state
  });

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ProAuthProvider()),
          ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
        ],
        child: const MaterialApp(home: ProSubscriptionScreen()),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// The offer cards are tall and the ListView mounts lazily — drag until
  /// the target is built, then bring it fully into view.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
    }
    expect(finder, findsWidgets);
    await tester.ensureVisible(finder.first);
    await tester.pump();
  }

  testWidgets(
      'SETUP: the picker headline + three cards with anchors, '
      'seats and « 3 mois offerts »', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(
      find.text('Choisissez votre offre — 3 mois offerts'),
      findsOneWidget,
    );
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('5 places'), findsOneWidget);
    await scrollTo(tester, find.text('Business'));
    expect(find.text('15 places'), findsOneWidget);
    await scrollTo(tester, find.text('Réseau'));
    expect(find.text('Sur devis'), findsOneWidget);
    expect(find.text('15 places par salon'), findsOneWidget);
    // R6: multi-salons is LIVE — the entitlement no longer says bientôt.
    expect(
      find.text('Multi-salons — ajoutez des salons à votre compte'),
      findsOneWidget,
    );
  });

  testWidgets(
      'choosing Pro starts the trial: snackbar + banner + seats bar '
      '+ « Votre offre » badge', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Choisir').first);
    await settle(tester);

    expect(find.textContaining('Offre Pro choisie'), findsOneWidget);
    expect(find.textContaining('Essai gratuit'), findsOneWidget);
    await scrollTo(tester, find.text('Votre offre'));
    await scrollTo(tester, find.text('Changer d\'offre').first);
    await scrollTo(
      tester,
      find.text('Le changement d\'offre conserve votre période d\'essai.'),
    );
  });

  testWidgets('GRACE: the urgent banner + WhatsApp CTA', (tester) async {
    subs.inner = MockSubscriptionService(
      initial: state(status: SalonOfferStatus.grace),
    );
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Votre offre a expiré'), findsOneWidget);
    expect(find.textContaining('dépublication'), findsOneWidget);
    expect(find.text('Nous contacter'), findsWidgets);
  });

  testWidgets(
      'EXPIRED + unpublished: « Salon dépublié » with the '
      'data-intact reassurance; a re-choice surfaces trial_used',
      (tester) async {
    subs.inner = MockSubscriptionService(
      initial: state(status: SalonOfferStatus.expired, unpublished: true),
    );
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Salon dépublié'), findsOneWidget);
    expect(find.textContaining('vos données sont intactes'), findsOneWidget);

    // `.first` throws on an empty candidate set while scrolling — reach
    // the Business card by its (unique) name first.
    await scrollTo(tester, find.text('Business'));
    await tester.tap(find.text('Changer d\'offre').first);
    await settle(tester);
    // The trial-used notice lands ABOVE the cards — scroll back up.
    for (var i = 0;
        i < 20 &&
            find
                .text('Votre essai gratuit a déjà été utilisé.')
                .evaluate()
                .isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pump();
    }
    expect(
      find.text('Votre essai gratuit a déjà été utilisé.'),
      findsOneWidget,
    );
  });

  testWidgets('a bare member account gets the owner-only guard',
      (tester) async {
    auth.current = ProviderUser(
      id: 'member_1',
      phoneNumber: '',
      businessName: '',
      businessType: BusinessType.other,
      email: 'x@b.com',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Réservé au propriétaire'), findsOneWidget);
  });
}
