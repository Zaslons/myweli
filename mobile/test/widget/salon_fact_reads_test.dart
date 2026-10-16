import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/providers/pro_salon_profile_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/profile/pro_profile_screen.dart';
import 'package:myweli/screens/provider/profile/pro_salon_profile_screen.dart';
import 'package:myweli/screens/provider/settings/deposit_settings_screen.dart';
import 'package:myweli/screens/provider/team/team_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// [signedInAs] answers `getCurrentProvider` while it is set — the same
/// account with another KYC status, for the verification test.
class _Auth extends MockAuthService {
  ProviderUser? signedInAs;

  @override
  Future<ProviderUser?> getCurrentProvider() async =>
      signedInAs ?? super.getCurrentProvider();
}

/// The mock world with two knobs on `GET /me/provider`: [myProviderGate]
/// holds the answer back (a cold start whose probe has not landed),
/// [myProviderAnswer] replaces it (offline).
class _ProService extends MockProService {
  Completer<void>? myProviderGate;
  ApiResponse<MyProviderInfo>? myProviderAnswer;

  void reset() {
    myProviderGate = null;
    myProviderAnswer = null;
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    final gate = myProviderGate;
    if (gate != null) await gate.future;
    return myProviderAnswer ?? super.getMyProvider(salonId: salonId);
  }
}

/// What the ACCOUNT says (`ProviderUser` — a registration-time copy of the
/// default salon): none of it may describe the acting salon.
const _accountFacts = [
  'Salon Excellence',
  'Barbier',
  'Cocody, Angré 7ème Tranche',
  '+2250711223344',
  '+225 07 11 22 33 44',
];

/// R6 salon-FACT reads (docs/design/r6-salon-fact-reads.md): « Profil » and
/// « Équipe » describe the ACTING salon (`ProAuthProvider.activeSalon` /
/// `salonName`), never the account's `businessName`, `businessType`,
/// `address` or `phoneNumber`. Verification is the one account fact that
/// stays (KYC is per account — §1.3), pinned at the bottom. The salon-ID twin
/// of this file is salon_id_reads_test.dart (#625).
void main() {
  final auth = _Auth();
  final pro = _ProService();
  final seededSalons = List<models.Provider>.of(MockData.providers);

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = pro;
    serviceLocator.providerService = MockProviderService();
    serviceLocator.proArtistService = MockProArtistService();
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.localityService = MockLocalityService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    // The rename test writes through the mock's PATCH.
    MockData.providers
      ..clear()
      ..addAll(seededSalons);
    ProSalonScope.clear();
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    pro.reset();
    auth.signedInAs = null;
    await auth.logoutProvider();
  });

  /// « Mes salons » loaded. `loadMySalons` returns at once while the
  /// constructor's own call is in flight, so poll rather than await it.
  Future<void> salonsLoaded(ProAuthProvider session) async {
    await session.loadMySalons();
    for (var i = 0; i < 60 && !session.hasMultipleSalons; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(session.hasMultipleSalons, isTrue, reason: 'the test');
  }

  /// The demo owner (provider1 by default, owner of provider2 too), switched
  /// to [salonId] — the R6 « Mes salons » move — with « Mes salons » loaded,
  /// so the Profil row reads « 2 salons — actif : … » deterministically.
  Future<ProAuthProvider> ownerSwitchedTo(
    WidgetTester tester,
    String salonId,
  ) async {
    final session = await signInPro(tester);
    await tester.runAsync(() async {
      expect(await session.switchSalon(salonId), isTrue);
      await salonsLoaded(session);
    });
    expect(session.activeSalonId, salonId);
    expect(session.provider!.providerId, isNot(salonId), reason: 'the test');
    return session;
  }

  /// A tall surface: the « Profil » column and the salon-profile form both
  /// run past 600dp, and a test that scrolls is a test about scrolling.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget profileApp(ProAuthProvider session) {
    final router = GoRouter(
      initialLocation: '/pro/profile',
      routes: [
        GoRoute(
          path: '/pro/profile',
          builder: (_, _) => const ProProfileScreen(),
        ),
        GoRoute(
          path: '/pro/salon-profile',
          builder: (_, _) => const ProSalonProfileScreen(),
        ),
      ],
    );
    return wrapApp(
      providers: [
        ChangeNotifierProvider<ProAuthProvider>.value(value: session),
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ChangeNotifierProvider(create: (_) => ProSalonProfileProvider()),
      ],
      routerConfig: router,
    );
  }

  void expectNoAccountFacts() {
    for (final fact in _accountFacts) {
      expect(
        find.text(fact),
        findsNothing,
        reason: '« $fact » is the account\'s, not the acting salon\'s',
      );
    }
  }

  testWidgets('« Profil » after a switch: the owner card describes the '
      'switched-to salon', (tester) async {
    tallSurface(tester);
    final session = await ownerSwitchedTo(tester, 'provider2');

    await tester.pumpWidget(profileApp(session));
    await settleMocks(tester);

    expectNoAccountFacts();
    expect(find.text('Beauté Divine'), findsOneWidget);
    expect(find.text('Salon de coiffure'), findsOneWidget);
    expect(find.text('Marcory, Zone 4'), findsOneWidget);
    expect(find.text('+225 05 44 55 66 77'), findsOneWidget);
    expect(find.text('Nom du salon'), findsOneWidget);
    expect(find.text('Catégorie'), findsOneWidget);
  });

  testWidgets('« Profil » after renaming the salon in « Profil du salon »: '
      'the card shows the new name — no switch needed', (tester) async {
    // The account's name is written once, at sign-up; the salon's is edited
    // here. A one-salon owner saw the registration name forever.
    tallSurface(tester);
    final session = await signInPro(tester);
    await tester.runAsync(() => salonsLoaded(session));

    await tester.pumpWidget(profileApp(session));
    await settleMocks(tester);
    expect(find.text('Salon Excellence'), findsOneWidget, reason: 'before');

    await tester.tap(find.text('Profil du salon'));
    await settleMocks(tester, rounds: 2);
    // The form's first field is the name (pro_salon_profile_form_test).
    await tester.enterText(find.byType(TextField).at(0), 'Excellence Prestige');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    // PATCH, then GET /me/provider and GET /me/salons.
    await settleMocks(tester, rounds: 3);

    expect(find.text('Mes salons'), findsOneWidget, reason: 'back on Profil');
    expect(find.text('Salon Excellence'), findsNothing);
    expect(find.text('Excellence Prestige'), findsOneWidget);
    expect(find.text('2 salons — actif : Excellence Prestige'), findsOneWidget);
  });

  testWidgets('cold start before GET /me/provider lands: the salon\'s name '
      'and a skeleton — never the account\'s fields', (tester) async {
    final semantics = tester.ensureSemantics();
    tallSurface(tester);
    // A switch persists the selection and caches provider2's membership —
    // what a later cold start restores from.
    await ownerSwitchedTo(tester, 'provider2');
    pro.myProviderGate = Completer<void>();
    late ProAuthProvider session;
    await tester.runAsync(() async {
      session = ProAuthProvider();
      await session.restored;
    });
    expect(session.activeSalon, isNull, reason: 'the scenario');
    expect(session.isLoading, isTrue, reason: 'the scenario');

    await tester.pumpWidget(profileApp(session));
    await tester.pump();

    expectNoAccountFacts();
    expect(find.text('Beauté Divine'), findsWidgets);
    expect(
      find.bySemanticsLabel('Chargement des informations du salon'),
      findsOneWidget,
    );

    // The probe lands.
    await tester.runAsync(() async {
      pro.myProviderGate!.complete();
      for (var i = 0; i < 60 && session.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    // Also drains the screen's own invitations read.
    await settleMocks(tester);

    expect(find.text('Marcory, Zone 4'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Chargement des informations du salon'),
      findsNothing,
    );
    expectNoAccountFacts();
    semantics.dispose();
  });

  testWidgets('offline: the card says the salon could not be loaded, and '
      '« Réessayer » brings it once the network is back', (tester) async {
    final semantics = tester.ensureSemantics();
    tallSurface(tester);
    await ownerSwitchedTo(tester, 'provider2');
    pro.myProviderAnswer = ApiResponse.error(
      'Connexion impossible.',
      code: 'network',
    );
    late ProAuthProvider session;
    await tester.runAsync(() async {
      session = ProAuthProvider();
      await session.ready;
    });
    expect(session.activeSalon, isNull, reason: 'the scenario');
    expect(session.isLoading, isFalse, reason: 'the scenario');

    await tester.pumpWidget(profileApp(session));
    await tester.pump();

    expectNoAccountFacts();
    expect(find.text('Beauté Divine'), findsWidgets);
    expect(
      find.text(
        'Les informations du salon n’ont pas pu être chargées. '
        'Vérifiez votre connexion.',
      ),
      findsOneWidget,
    );

    pro.myProviderAnswer = null; // the network is back
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    // The retry is in flight: the loading shape, not the same sentence.
    expect(
      find.bySemanticsLabel('Chargement des informations du salon'),
      findsOneWidget,
    );
    await settleMocks(tester, rounds: 2);

    expect(find.text('Marcory, Zone 4'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
    expectNoAccountFacts();
    semantics.dispose();
  });

  testWidgets('« Équipe » after a switch: the revoke confirmation names the '
      'switched-to salon', (tester) async {
    final session = await ownerSwitchedTo(tester, 'provider2');

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: session),
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
          ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
          ChangeNotifierProvider(create: (_) => ProArtistProvider()),
        ],
        home: const TeamScreen(),
      ),
    );
    await settleMocks(tester, rounds: 2);

    // provider2's roster: Jean (owner) + a re-invited réception.
    await tester.tap(find.text('ancien.membre@myweli.test'));
    await settleMocks(tester);
    await tester.tap(find.text('Révoquer l’accès'));
    await settleMocks(tester);

    expect(find.text('Révoquer l’accès ?'), findsOneWidget);
    expect(
      find.textContaining('perdra immédiatement l’accès à Beauté Divine.'),
      findsOneWidget,
    );
    expect(find.textContaining('Salon Excellence'), findsNothing);
  });

  group('salonName with no membership (a legacy session, offline)', () {
    Future<ProAuthProvider> coldStartOffline(WidgetTester tester) async {
      pro.myProviderAnswer = ApiResponse.error(
        'Connexion impossible.',
        code: 'network',
      );
      late ProAuthProvider session;
      await tester.runAsync(() async {
        session = ProAuthProvider();
        await session.ready;
      });
      expect(session.membership, isNull, reason: 'the scenario');
      return session;
    }

    Future<void> signInWithoutMembership(WidgetTester tester) =>
        tester.runAsync(() async {
          await auth.requestProviderEmailOtp('jean@salon-excellence.test');
          final res = await auth.verifyProviderEmailOtp(
            'jean@salon-excellence.test',
            MockAuthService.demoOtp,
          );
          expect(res.signedIn, isTrue);
        });

    testWidgets('the default salon: the account\'s name is the copy it was '
        'made from', (tester) async {
      await signInWithoutMembership(tester);
      final session = await coldStartOffline(tester);
      expect(session.selectedSalonId, isNull);
      expect(session.salonName, 'Salon Excellence');
    });

    testWidgets('a switched-to salon: never the account\'s name', (
      tester,
    ) async {
      await signInWithoutMembership(tester);
      await tester.runAsync(() => auth.setSelectedProviderSalon('provider2'));
      final session = await coldStartOffline(tester);
      expect(session.selectedSalonId, 'provider2');
      expect(session.salonName, 'votre salon');
    });
  });

  testWidgets('verification stays the ACCOUNT\'s after a switch — KYC is per '
      'account (spec §1.3): « Profil » and the Acompte lock both follow it', (
    tester,
  ) async {
    tallSurface(tester);
    final jean = MockData.providerUsers.firstWhere(
      (u) => u.email == 'jean@salon-excellence.test',
    );
    auth.signedInAs = jean.copyWith(
      verificationStatus: VerificationStatus.pending,
    );
    // provider2's badge says « verified »: the screens must not read it.
    final i = MockData.providers.indexWhere((p) => p.id == 'provider2');
    MockData.providers[i] = models.Provider.fromJson({
      ...MockData.providers[i].toJson(),
      'verified': true,
    });
    final session = await ownerSwitchedTo(tester, 'provider2');
    expect(session.activeSalon!.verified, isTrue, reason: 'the test');

    await tester.pumpWidget(profileApp(session));
    await settleMocks(tester);
    expect(find.text('Vérification'), findsOneWidget);
    expect(find.text('En attente de vérification'), findsOneWidget);
    expect(find.text('Compte vérifié'), findsNothing);

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: session),
          ChangeNotifierProvider(create: (_) => ProDepositSettingsProvider()),
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        home: const DepositSettingsScreen(providerId: 'provider2'),
      ),
    );
    await settleMocks(tester, rounds: 2);
    expect(
      find.textContaining('après la vérification de votre compte'),
      findsOneWidget,
    );
  });
}
