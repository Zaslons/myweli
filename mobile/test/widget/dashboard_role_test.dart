import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';

/// Team access R4b §5.3 — the role-shaped dashboard: owner full, manager
/// without money/Configurer, réception down to Rendez-vous + Clients, and
/// the « Bienvenue, {salon} » header for members.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = MockAuthService();

  setUpAll(() async {
    await loadRealFonts();
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    // `late final`: one service for the file; the shoot test switches on
    // the shoot's figures (below) and off again.
    serviceLocator.proService = _ShootFigures();
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
      final res = await auth.verifyProviderEmailOtp(
        email,
        MockAuthService.demoOtp,
      );
      expect(res.signedIn, isTrue);
    });
  }

  Widget app(
    ProAuthProvider authProvider, {
    double scale = 1,
    bool realFonts = false,
  }) {
    final router = GoRouter(
      initialLocation: '/pro/dashboard',
      routes: [
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, _) => const DashboardScreen(),
        ),
      ],
    );
    return wrapApp(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
        // The bell's feed (its unread badge) — the pro app runs the shared
        // NotificationsProvider on its own session.
        ChangeNotifierProvider(
          create: (_) =>
              NotificationsProvider(service: MockNotificationService()),
        ),
      ],
      routerConfig: router,
      theme: realFonts ? AppTheme.themeData(fontFamily: kRealFont) : null,
      builder: scale == 1
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
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
      for (
        var i = 0;
        i < 60 &&
            (authProvider.isLoading ||
                (authProvider.isAuthenticated &&
                    authProvider.membership == null));
        i++
      ) {
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

  testWidgets('MANAGER: no money cards, no Configurer, catalogue kept, '
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

  testWidgets('RÉCEPTION: stats + Rendez-vous + Clients only; empty '
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

  /// docs/design/pro-screenshot-shoot-fixes.md §2.4 — the two cards of a
  /// stat row are one height. They were plain `Expanded`s: on the demo salon
  /// « 114 000 FCFA » wrapped in « Ce mois » and not in « Aujourd’hui ».
  /// The shoot's figures, in real fonts — with every figure at « 0 » the two
  /// cards hold the same text and are one height with or without the fix.
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('OWNER: each stat row\'s cards share one height (360dp, '
        '$scale×, the shoot\'s figures)', (tester) async {
      _ShootFigures.on = true;
      addTearDown(() => _ShootFigures.on = false);
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loginAs(tester, 'jean@salon-excellence.test');
      await tester.pumpWidget(
        app(await readyAuth(tester), scale: scale, realFonts: true),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);

      Rect card(Finder title) => tester.getRect(
        find.ancestor(of: title, matching: find.byType(Container)).first,
      );
      final today = find.text('Aujourd’hui');
      expect(today, findsNWidgets(2), reason: 'rendez-vous + revenus rows');
      final pending = card(find.text('En attente'));
      final todayAppts = card(today.first);
      expect(todayAppts.height, closeTo(pending.height, 0.5));
      final month = card(find.text('Ce mois'));
      final todayMoney = card(today.last);
      expect(
        todayMoney.height,
        closeTo(month.height, 0.5),
        reason: '« 0 FCFA » beside « 114 000 FCFA » at $scale×',
      );
    });
  }
}

/// The mock, except — while [on] — the demo salon's figures on the day of the
/// shoot: an empty « Aujourd’hui » beside a month whose amount wraps.
class _ShootFigures extends MockProService {
  static bool on = false;

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    String providerId,
  ) async => !on
      ? super.getDashboardStats(providerId)
      : ApiResponse.success(
          const DashboardStats(
            todayAppointments: 0,
            pendingRequests: 3,
            totalAppointments: 41,
            todayRevenue: 0,
            weekRevenue: 32000,
            monthRevenue: 114000,
          ),
        );
}
