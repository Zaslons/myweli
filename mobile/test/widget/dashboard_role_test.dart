import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/formatters.dart';
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

import '../a11y/_a11y.dart';
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

  /// The stat cards (docs/design/amounts-that-fit.md §2, and
  /// pro-screenshot-shoot-fixes.md §2.4 before it): two across, or ALL of
  /// them one per row when a value would not fit a half-width card; within a
  /// row the cards are one height; no amount is ever broken inside its number.
  ///
  /// Real figures, in real fonts — with every figure at « 0 » the cards hold
  /// the same text and are one height, and « fits », with or without the fix.
  for (final (what, figures, login, scale, cards, perRow) in [
    // The shoot's figures: « 0 FCFA » beside « 114 000 FCFA ».
    ('the shoot at 1×', _shoot, _owner, 1.0, 4, 2),
    ('the shoot at 1.3×', _shoot, _owner, 1.3, 4, 2),
    // 126dp per half card; « 114 000 » at 48sp needs 171. Was broken inside
    // the number, and pinned as a known violation until the block measured.
    ('the shoot at 2×', _shoot, _owner, 2.0, 4, 1),
    // §2's stated target: nine digits whole at 200 % on 360dp.
    ('nine digits at 2×', _nineDigits, _owner, 2.0, 4, 1),
    // Seven digits do not fit a half card even at the default size.
    ('seven digits at 1×', _sevenDigits, _owner, 1.0, 4, 2),
    ('seven digits at 1.3×', _sevenDigits, _owner, 1.3, 4, 1),
    // No finances.view: no money row, the two counts decide alone.
    ('reception (no money) at 2×', _shoot, _reception, 2.0, 2, 2),
  ]) {
    testWidgets('stat cards — $what: $perRow per row, whole, level', (
      tester,
    ) async {
      _ShootFigures.figures = figures;
      addTearDown(() => _ShootFigures.figures = null);
      tester.view.physicalSize = const Size(360, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loginAs(tester, login);
      await tester.pumpWidget(
        app(await readyAuth(tester), scale: scale, realFonts: true),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);

      // The cards, by their subtitle — unique per card where titles repeat.
      Rect cardOf(Finder inside) => tester.getRect(
        find.ancestor(of: inside, matching: find.byType(Container)).first,
      );
      final revenus = find.text('Revenus');
      final rects = [
        cardOf(find.text('Rendez-vous')),
        cardOf(find.text('Demandes')),
        // « Revenus » is also a section title lower down; the stat cards are
        // the first two renderings.
        if (cards == 4) ...[cardOf(revenus.at(0)), cardOf(revenus.at(1))],
      ];
      expect(rects, hasLength(cards));
      if (cards == 2) {
        expect(find.text('Ce mois'), findsNothing, reason: 'no money row');
      }

      // One shape for every card.
      bool sameRow(Rect a, Rect b) => a.top < b.bottom && b.top < a.bottom;
      for (var i = 0; i < rects.length; i++) {
        final inRow = rects.where((r) => sameRow(rects[i], r)).length;
        expect(inRow, perRow, reason: 'card $i at $scale×');
      }
      // Cards sharing a row share a height and a top.
      for (var i = 0; i + 1 < rects.length; i += 2) {
        if (perRow != 2) break;
        expect(rects[i + 1].height, closeTo(rects[i].height, 0.5));
        expect(rects[i + 1].top, closeTo(rects[i].top, 0.5));
      }

      // Every amount is whole — heights say nothing about that.
      if (cards == 4) {
        for (final amount in {
          Formatters.formatCurrency(figures.todayRevenue!),
          Formatters.formatCurrency(figures.monthRevenue!),
        }) {
          expectNoMidWordBreak(tester, amount, '« $amount » — $what');
        }
      }
      for (final label in ['En attente', 'Demandes']) {
        expectNoMidWordBreak(tester, label, '« $label » — $what');
      }
    });
  }
}

const _owner = 'jean@salon-excellence.test';
const _reception = 'fatou.reception@myweli.test';

const _shoot = DashboardStats(
  todayAppointments: 0,
  pendingRequests: 3,
  totalAppointments: 41,
  todayRevenue: 0,
  weekRevenue: 32000,
  monthRevenue: 114000,
);
const _sevenDigits = DashboardStats(
  todayAppointments: 4,
  pendingRequests: 1,
  totalAppointments: 320,
  todayRevenue: 85000,
  weekRevenue: 410000,
  monthRevenue: 1250000,
);
const _nineDigits = DashboardStats(
  todayAppointments: 12,
  pendingRequests: 0,
  totalAppointments: 9000,
  todayRevenue: 2400000,
  weekRevenue: 31000000,
  monthRevenue: 123456789,
);

/// The mock, except — while [figures] is set — those figures: the demo
/// salon's on the day of the shoot, or an amount long enough to need the
/// width. Money is still withheld from a role that may not see it, as the
/// mock does (the server field-gates it).
class _ShootFigures extends MockProService {
  static DashboardStats? figures;

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    String providerId,
  ) async {
    final base = await super.getDashboardStats(providerId);
    final f = figures;
    if (f == null || base.data == null) return base;
    final money = base.data!.hasRevenue;
    return ApiResponse.success(
      DashboardStats(
        todayAppointments: f.todayAppointments,
        pendingRequests: f.pendingRequests,
        totalAppointments: f.totalAppointments,
        todayRevenue: money ? f.todayRevenue : null,
        weekRevenue: money ? f.weekRevenue : null,
        monthRevenue: money ? f.monthRevenue : null,
      ),
    );
  }
}
