import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/formatters.dart';
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

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/surface.dart';

class _SwitchableAuth extends MockAuthService {
  ProviderUser? current;

  @override
  Future<ProviderUser?> getCurrentProvider() async => current;
}

/// Scenario-switchable offer state (each test picks its inner service) —
/// serviceLocator fields are late-final, so scenarios swap through `inner`.
class _SwitchableSubs implements SubscriptionServiceInterface {
  SubscriptionServiceInterface inner = MockSubscriptionService();

  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  ) => inner.getSalonSubscription(providerId);
}

/// « Mon abonnement » is READ-ONLY — the Pro app never sells (App Store
/// 3.1.3(f), docs/design/pro-companion-path.md §2.2): each state shows the
/// salon's current offer and nothing that chooses, switches, promotes or
/// points to where an offer is obtained. The key tests run on BOTH platforms
/// (`TargetPlatformVariant`): the rule is not a platform branch, and the
/// variant is what proves none exists — `flutter test` reports Android, so
/// without it an iOS-only branch would never render here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = _SwitchableAuth();
  final subs = _SwitchableSubs();
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  final trialEnd = DateTime.now().add(const Duration(days: 45));
  final graceEnd = DateTime.now().add(const Duration(days: 52));
  final paidUntil = DateTime.now().add(const Duration(days: 20));

  SalonSubscription state({
    SalonTier tier = SalonTier.pro,
    SalonOfferStatus status = SalonOfferStatus.trial,
    bool unpublished = false,
    DateTime? paid,
  }) => SalonSubscription(
    tier: tier,
    status: status,
    trialEndsAt: trialEnd,
    graceEndsAt: graceEnd,
    paidUntil: paid,
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
    MockData.resetTeam();
    auth.current = MockData.providerUsers.first;
    subs.inner = MockSubscriptionService(); // setup state
  });

  Widget app() => wrapApp(
    providers: [
      ChangeNotifierProvider(create: (_) => ProAuthProvider()),
      ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
    ],
    home: const ProSubscriptionScreen(),
  );

  /// Session load → offer load: two sequential mock calls.
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settleMocks(tester, rounds: 2);
  }

  /// The seat cap the mock derives from the tier, against the seeded team.
  String seatsLine(int cap) =>
      '${MockData.teamSeatsUsed(providerId: 'provider1')} / $cap places';

  /// Everything the read-only screen may never show, in any state, on any
  /// platform — the spec's §2.1 rule as finders. « Pro » / « Business » /
  /// « Réseau » are EXACT matches: they were the offer cards' titles, while
  /// the banner legitimately names the current tier inside a longer line
  /// (« Offre Réseau active »).
  List<Finder> forbidden() => [
    find.textContaining('Choisir'),
    find.textContaining('Choisissez'),
    find.textContaining('Changer d’offre'),
    find.textContaining('changement d’offre'),
    find.textContaining('mois offerts'),
    find.text('Votre offre'),
    find.text('Pro'),
    find.text('Business'),
    find.text('Réseau'),
    find.textContaining('Aide & Support'),
    find.textContaining('myweli.com'),
    find.textContaining('Tarif personnalisé'),
    find.textContaining('Réactivez'),
    find.textContaining('Activez'),
    find.textContaining('paie le mois'),
    find.textContaining('Réservations illimitées'),
    find.textContaining('Tout de l’offre'),
    find.textContaining('FCFA'),
    find.textContaining('Paiement à jour'),
    find.textContaining('essai gratuit a déjà'),
    // No button of any kind: the only control the screen keeps is the
    // live-Réseau « Ajouter un salon » row, which is a ListTile.
    find.byWidgetPredicate((w) => w is ButtonStyleButton),
  ];

  /// Walks the whole screen from the TOP to the BOTTOM and fails if any of
  /// [finders] matches at any point — `find` only sees built widgets, so one
  /// look at the first screen proves nothing about what is below it.
  ///
  /// **It jumps to the top first, and that is load-bearing.** A second
  /// `pumpWidget` of the same screen keeps the scroll offset, and an earlier
  /// version of this walk that started wherever the list was let a mutation
  /// survive — it began at the bottom and never saw the first card.
  ///
  /// **It asserts it reached the bottom**, so a list that grew past the walk's
  /// bound fails here instead of passing unseen.
  Future<void> expectNowhere(WidgetTester tester, List<Finder> finders) async {
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      for (final f in finders) {
        expect(f, findsNothing, reason: 'found on scroll step $i: $f');
      }
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pump();
    }
    expect(
      position.pixels,
      position.maxScrollExtent,
      reason: 'the walk never reached the bottom of the screen',
    );
    for (final f in finders) {
      expect(f, findsNothing);
    }
  }

  group('read-only on both platforms — no plan choice, no promotion, no '
      'pointer', () {
    testWidgets('SETUP (no offer row): the fact and when it changes — '
        'nothing else', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Pas encore d’offre active'), findsOneWidget);
      expect(
        find.text('Votre offre démarre à la mise en ligne de votre salon.'),
        findsOneWidget,
      );
      // « Nothing else » (§2.2): no seats, no reassurance footer, no card.
      expect(find.textContaining('places'), findsNothing);
      expect(find.text('Vos données ne sont jamais bloquées.'), findsNothing);
      // The old setup headline and line, gone with the picker.
      expect(find.textContaining('reste gratuit'), findsNothing);
      await expectNowhere(tester, forbidden());
    }, variant: bothPlatforms);

    testWidgets('TRIAL: the banner and the seats bar, no cards', (
      tester,
    ) async {
      subs.inner = MockSubscriptionService(initial: state());
      await pumpScreen(tester);

      expect(find.textContaining('Essai gratuit — '), findsOneWidget);
      expect(
        find.text(
          'Offre Pro · se termine le ${Formatters.formatDate(trialEnd)}',
        ),
        findsOneWidget,
      );
      expect(find.text(seatsLine(5)), findsOneWidget);
      expect(find.text('Vos données ne sont jamais bloquées.'), findsOneWidget);
      await expectNowhere(tester, forbidden());
    }, variant: bothPlatforms);

    testWidgets('PAID: « Offre {tier} active » until its date, seats, no '
        'cards', (tester) async {
      subs.inner = MockSubscriptionService(
        initial: state(
          tier: SalonTier.business,
          status: SalonOfferStatus.paid,
          paid: paidUntil,
        ),
      );
      await pumpScreen(tester);

      expect(find.text('Offre Business active'), findsOneWidget);
      expect(
        find.text('Jusqu’au ${Formatters.formatDate(paidUntil)}'),
        findsOneWidget,
      );
      expect(find.text(seatsLine(15)), findsOneWidget);
      await expectNowhere(tester, forbidden());
    }, variant: bothPlatforms);

    testWidgets('GRACE: urgent and dated, with no button', (tester) async {
      subs.inner = MockSubscriptionService(
        initial: state(status: SalonOfferStatus.grace),
      );
      await pumpScreen(tester);

      expect(find.text('Votre offre a expiré'), findsOneWidget);
      expect(
        find.text(
          'Période de grâce jusqu’au ${Formatters.formatDate(graceEnd)}.',
        ),
        findsOneWidget,
      );
      // The old line announced the unpublishing and, on Android, where to pay.
      expect(find.textContaining('dépublication'), findsNothing);
      await expectNowhere(tester, forbidden());
    }, variant: bothPlatforms);

    testWidgets('EXPIRED (still published): « Offre expirée », data intact, '
        'no button', (tester) async {
      subs.inner = MockSubscriptionService(
        initial: state(status: SalonOfferStatus.expired),
      );
      await pumpScreen(tester);

      expect(find.text('Offre expirée'), findsOneWidget);
      expect(find.text('Vos données sont intactes.'), findsOneWidget);
      await expectNowhere(tester, forbidden());
    }, variant: bothPlatforms);

    testWidgets('EXPIRED + unpublished: « Salon dépublié » with the '
        'reassurance, no button', (tester) async {
      subs.inner = MockSubscriptionService(
        initial: state(status: SalonOfferStatus.expired, unpublished: true),
      );
      await pumpScreen(tester);

      expect(find.text('Salon dépublié'), findsOneWidget);
      expect(
        find.text(
          'Votre salon n’est plus visible des clients. '
          'Vos données sont intactes.',
        ),
        findsOneWidget,
      );
      await expectNowhere(tester, forbidden());
    }, variant: bothPlatforms);

    testWidgets('LIVE RÉSEAU: « Ajouter un salon » states what the offer '
        'allows — never another offer or a trial', (tester) async {
      subs.inner = MockSubscriptionService(
        initial: state(tier: SalonTier.reseau),
      );
      await pumpScreen(tester);

      expect(
        find.text(
          'Offre Réseau · se termine le ${Formatters.formatDate(trialEnd)}',
        ),
        findsOneWidget,
      );
      expect(find.text('Ajouter un salon'), findsOneWidget);
      expect(find.text('Un salon de plus dans votre compte.'), findsOneWidget);
      expect(find.textContaining('propre essai'), findsNothing);
      await expectNowhere(tester, forbidden());
    }, variant: bothPlatforms);
  });

  testWidgets('PAID with no `paidUntil`: the title alone — the dead « Paiement '
      'à jour » fallback is gone', (tester) async {
    subs.inner = MockSubscriptionService(
      initial: state(status: SalonOfferStatus.paid),
    );
    await pumpScreen(tester);

    expect(find.text('Offre Pro active'), findsOneWidget);
    expect(find.textContaining('Jusqu’au'), findsNothing);
    expect(find.textContaining('Paiement à jour'), findsNothing);
  });

  testWidgets('an EXPIRED Réseau offer does not open « Ajouter un salon »', (
    tester,
  ) async {
    subs.inner = MockSubscriptionService(
      initial: state(tier: SalonTier.reseau, status: SalonOfferStatus.expired),
    );
    await pumpScreen(tester);

    expect(find.text('Offre expirée'), findsOneWidget);
    expect(find.text('Ajouter un salon'), findsNothing);
  });

  testWidgets('« Ajouter un salon » opens the add-salon form', (tester) async {
    subs.inner = MockSubscriptionService(
      initial: state(tier: SalonTier.reseau),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ProSubscriptionScreen()),
        GoRoute(
          path: '/pro/salons/nouveau',
          builder: (_, _) => const Scaffold(body: Text('NOUVEAU SALON')),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => ProAuthProvider()),
          ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
        ],
        routerConfig: router,
      ),
    );
    await settleMocks(tester, rounds: 2);

    await tester.tap(find.text('Ajouter un salon'));
    await settleMocks(tester);
    expect(find.text('NOUVEAU SALON'), findsOneWidget);
  });

  testWidgets('200 % text on a 360dp phone: the longest state lays out '
      'without overflow', (tester) async {
    pinSurface(tester, size: kFloorPhone, scale: 2.0);
    subs.inner = MockSubscriptionService(
      initial: state(status: SalonOfferStatus.expired, unpublished: true),
    );
    await pumpScreen(tester);

    expect(find.text('Salon dépublié'), findsOneWidget);
    await expectNowhere(tester, forbidden());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a load failure offers a retry, not a dead end', (tester) async {
    subs.inner = _FailingSubs();
    await pumpScreen(tester);

    expect(find.text('Une erreur est survenue'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('a bare member account gets the owner-only guard', (
    tester,
  ) async {
    auth.current = ProviderUser(
      id: 'member_1',
      phoneNumber: '',
      businessName: '',
      businessType: BusinessType.other,
      email: 'x@b.com',
      createdAt: DateTime(2026),
    );
    await pumpScreen(tester);
    expect(find.text('Réservé au propriétaire'), findsOneWidget);
  });
}

class _FailingSubs implements SubscriptionServiceInterface {
  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  ) async => ApiResponse.error('Pas de connexion. Réessayez.');
}
