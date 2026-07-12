import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/team/team_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The current mock session — owner by default, switchable to a bare
/// member account for the guard test.
class _SwitchableAuth extends MockAuthService {
  ProviderUser? current;

  @override
  Future<ProviderUser?> getCurrentProvider() async => current;
}

/// Team access R3 §2.1 — the Équipe screen: roster states, role chips,
/// pending/expired badges, seats header, owner protection and the
/// revoke confirmation copy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = _SwitchableAuth();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.proArtistService = MockProArtistService();
    serviceLocator.subscriptionService = MockSubscriptionService(
      initial: SalonSubscription(
        tier: SalonTier.pro,
        status: SalonOfferStatus.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 60)),
        graceEndsAt: DateTime.now().add(const Duration(days: 67)),
        seats: const SalonSeats(cap: 5, used: 0),
      ),
    );
  });

  setUp(() {
    MockData.resetTeam();
    auth.current = MockData.providerUsers.first; // owner of provider1
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/pro/team',
      routes: [
        GoRoute(path: '/pro/team', builder: (_, __) => const TeamScreen()),
        GoRoute(
          path: '/pro/subscription',
          builder: (_, __) => const Scaffold(body: Text('OFFRES')),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => ProArtistProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets(
      'roster renders: owner pinned + chips + pending/expired '
      'badges + artist link + the seats header', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('jean@salon-excellence.test'), findsOneWidget);
    expect(find.text('Propriétaire'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('Collaborateur'), findsOneWidget);
    expect(find.text('Réception'), findsOneWidget);
    expect(find.text('Employé : Kouassi Jean'), findsOneWidget);
    expect(find.textContaining('Invitation envoyée'), findsOneWidget);
    expect(find.textContaining('Expirée'), findsOneWidget);
    // Seats derive live: owner + manager + unexpired staff invite = 3.
    expect(find.text('3 / 5 places'), findsOneWidget);
    expect(find.text('Inviter un membre'), findsOneWidget); // the FAB
  });

  testWidgets(
      'the owner row is inert; a member row opens the actions '
      'sheet with the revoke confirmation copy', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('jean@salon-excellence.test'));
    await tester.pump();
    expect(find.text('Révoquer l\'accès'), findsNothing);

    await tester.tap(find.text('awa.manager@myweli.test'));
    await settle(tester);
    expect(find.text('Changer le rôle'), findsOneWidget);
    expect(find.text('Révoquer l\'accès'), findsOneWidget);

    await tester.tap(find.text('Révoquer l\'accès'));
    await settle(tester);
    expect(find.text('Révoquer l\'accès ?'), findsOneWidget);
    expect(
      find.textContaining('perdra immédiatement l\'accès'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Son compte MyWeli n\'est pas supprimé.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Révoquer'));
    await settle(tester);
    await settle(tester);
    expect(find.text('Accès révoqué'), findsOneWidget);
  });

  testWidgets(
      'a pending row offers « Renvoyer l\'invitation » with the '
      'remaining budget', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('invitee@myweli.test'));
    await settle(tester);
    expect(find.text('Renvoyer l\'invitation (3 restants)'), findsOneWidget);
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
