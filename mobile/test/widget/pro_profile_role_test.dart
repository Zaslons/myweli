import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/profile/pro_profile_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Team access R4b §5.3 — the role-shaped Profil: owner keeps every row;
/// manager loses money/team/owner rows; staff is the slim personal profile
/// with the member header card (« Salon » + role chip).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = MockAuthService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = MockProService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
    serviceLocator.proTeamService = MockProTeamService();
  });

  setUp(() async {
    MockData.resetTeam();
    await auth.logoutProvider();
  });

  /// FakeAsync-safe pre-pump login (real mock delays need runAsync).
  Future<void> loginAs(WidgetTester tester, String email) async {
    await tester.runAsync(() async {
      await auth.requestProviderEmailOtp(email);
      final res =
          await auth.verifyProviderEmailOtp(email, MockAuthService.demoOtp);
      expect(res.signedIn, isTrue);
    });
  }

  Widget app(ProAuthProvider authProvider) {
    final router = GoRouter(
      initialLocation: '/pro/profile',
      routes: [
        GoRoute(
          path: '/pro/profile',
          builder: (_, __) => const ProProfileScreen(),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// The splash contract: the auth provider finishes loading (incl. the
  /// membership refresh) BEFORE any screen mounts. The constructor's own
  /// load chain races an explicit await (single-flight), so poll in REAL
  /// async until the membership lands.
  Future<ProAuthProvider> readyAuth(WidgetTester tester) async {
    late ProAuthProvider authProvider;
    await tester.runAsync(() async {
      authProvider = ProAuthProvider();
      for (var i = 0;
          i < 60 &&
              (authProvider.isLoading ||
                  (authProvider.isAuthenticated &&
                      authProvider.membership == null));
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    return authProvider;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> scrollDown(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -600),
    );
    await tester.pump();
  }

  testWidgets(
      'MANAGER: catalogue/profil-salon rows kept; money, team and '
      'owner rows gone; member header card', (tester) async {
    await loginAs(tester, 'awa.manager@myweli.test');
    await tester.pumpWidget(app(await readyAuth(tester)));
    await settle(tester);

    // Member header: name + « Salon » row + role chip.
    expect(find.text('Awa Traoré'), findsOneWidget);
    expect(find.text('Salon'), findsOneWidget);
    expect(find.text('Salon Excellence'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('Nom de l\'entreprise'), findsNothing);

    expect(find.text('Profil du salon'), findsOneWidget);
    expect(find.text('Configurer mon profil'), findsNothing);
    expect(find.text('Vérification'), findsNothing);
    expect(find.text('Équipe'), findsNothing);
    expect(find.text('Mon abonnement'), findsNothing);
    expect(find.text('Paramètres d\'acompte'), findsNothing);
    await scrollDown(tester);
    expect(find.text('Photos du salon'), findsOneWidget);
    expect(find.text('Avant / Après'), findsOneWidget);
    expect(find.text('Mes données'), findsNothing);
    await scrollDown(tester);
    expect(find.text('Déconnexion'), findsOneWidget);
  });

  testWidgets('STAFF: the slim personal profile — no salon rows at all',
      (tester) async {
    await loginAs(tester, 'sonia.staff@myweli.test');
    await tester.pumpWidget(app(await readyAuth(tester)));
    await settle(tester);

    expect(find.text('Sonia Koné'), findsOneWidget);
    expect(find.text('Collaborateur'), findsOneWidget);
    expect(find.text('Salon Excellence'), findsOneWidget);
    expect(find.text('Profil du salon'), findsNothing);
    expect(find.text('Photos du salon'), findsNothing);
    expect(find.text('Équipe'), findsNothing);
    expect(find.text('Mon abonnement'), findsNothing);
    await scrollDown(tester);
    expect(find.text('Déconnexion'), findsOneWidget);
    expect(find.text('Supprimer mon compte'), findsOneWidget);
  });

  testWidgets('OWNER keeps the business card and every row', (tester) async {
    await tester.runAsync(() async {
      await auth.requestProviderEmailOtp('own@profil.test');
      await auth.registerProviderWithEmail(
        email: 'own@profil.test',
        code: MockAuthService.demoOtp,
        phoneNumber: '+2250700000096',
        businessName: 'Salon Profil',
        businessType: BusinessType.salon,
      );
    });
    await tester.pumpWidget(app(await readyAuth(tester)));
    await settle(tester);

    expect(find.text('Nom de l\'entreprise'), findsOneWidget);
    expect(find.text('Configurer mon profil'), findsOneWidget);
    expect(find.text('Équipe'), findsOneWidget);
    await scrollDown(tester);
    expect(find.text('Mon abonnement'), findsOneWidget);
    expect(find.text('Paramètres d\'acompte'), findsOneWidget);
  });
}
