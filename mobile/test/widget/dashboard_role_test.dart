import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Team access R4b §5.3 — the role-shaped dashboard: owner full, manager
/// without money/Configurer, réception down to Rendez-vous + Clients, and
/// the « Bienvenue, {salon} » header for members.
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
  });

  setUp(() async {
    MockData.resetTeam();
    await auth.logoutProvider();
  });

  /// testWidgets runs in FakeAsync — real mock delays only complete inside
  /// runAsync, so the pre-pump login happens there.
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
      initialLocation: '/pro/dashboard',
      routes: [
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, __) => const DashboardScreen(),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
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

  testWidgets(
      'MANAGER: no money cards, no Configurer, catalogue kept, '
      'salonName header', (tester) async {
    await loginAs(tester, 'awa.manager@myweli.test');
    await tester.pumpWidget(app(await readyAuth(tester)));
    await settle(tester);

    expect(find.text('Bienvenue, Salon Excellence'), findsOneWidget);
    expect(find.text('Configurer mon profil'), findsNothing);
    expect(find.text('Revenus'), findsNothing); // stat cards AND grid card
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Employés'), findsOneWidget);
    expect(find.text('Disponibilité'), findsOneWidget);
    expect(find.text('Avis'), findsOneWidget);
    expect(find.text('Analyses'), findsOneWidget);
  });

  testWidgets(
      'RÉCEPTION: stats + Rendez-vous + Clients only; empty '
      'sections vanish', (tester) async {
    await loginAs(tester, 'fatou.reception@myweli.test');
    await tester.pumpWidget(app(await readyAuth(tester)));
    await settle(tester);

    expect(find.text('Rendez-vous'), findsWidgets);
    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Services'), findsNothing);
    expect(find.text('Disponibilité'), findsNothing);
    expect(find.text('Revenus'), findsNothing);
    expect(find.text('Avis'), findsNothing);
    // Whole sections are omitted when empty.
    expect(find.text('Configuration'), findsNothing);
    expect(find.text('Analyses'), findsNothing);
  });

  testWidgets('OWNER keeps the full dashboard incl. money', (tester) async {
    await tester.runAsync(() async {
      await auth.requestProviderEmailOtp('own@dash.test');
      await auth.registerProviderWithEmail(
        email: 'own@dash.test',
        code: MockAuthService.demoOtp,
        phoneNumber: '+2250700000097',
        businessName: 'Salon Dash',
        businessType: BusinessType.salon,
      );
    });
    await tester.pumpWidget(app(await readyAuth(tester)));
    await settle(tester);

    expect(find.text('Bienvenue, Salon Dash'), findsOneWidget);
    expect(find.text('Configurer mon profil'), findsOneWidget);
    expect(find.text('Revenus'), findsWidgets); // stat cards + Analyses card
    expect(find.text('Services'), findsOneWidget);
  });
}
