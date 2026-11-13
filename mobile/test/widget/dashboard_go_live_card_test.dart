import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/salon_validation_copy.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// GET /me/provider, steerable: [meFails] answers no read at all (a cold
/// start offline), [legacyServer] answers as a server from before B0.18
/// (no `validation` key).
class _Pro extends MockProService {
  bool meFails = false;
  bool legacyServer = false;

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({SalonId? salonId}) async {
    if (meFails) {
      return ApiResponse.error(
        'Connexion au serveur impossible',
        code: 'network',
      );
    }
    final res = await super.getMyProvider(salonId: salonId);
    final data = res.data;
    if (!legacyServer || data == null) return res;
    return ApiResponse.success(
      MyProviderInfo(salon: data.salon, membership: data.membership),
    );
  }
}

const _owner = 'jean@salon-excellence.test';
const _p1 = SalonId('provider1');

/// « Accueil »'s « Configurer mon profil » card: its subtitle follows where
/// the salon stands with MyWeli's validation (B0.18 — salon-go-live-approval
/// §6.2; decision 136 item 1, « as the website »), and keeps today's words
/// while the state is unknown (an offline cold start) or on a server from
/// before B0.18.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = MockAuthService();
  final pro = _Pro();
  final subs = MockSubscriptionService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = pro;
    serviceLocator.subscriptionService = subs;
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    subs.resetForTests();
    pro
      ..meFails = false
      ..legacyServer = false;
    await auth.logoutProvider();
  });

  Widget app(ProAuthProvider authProvider) => wrapApp(
    providers: [
      ChangeNotifierProvider.value(value: authProvider),
      ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
      ChangeNotifierProvider(
        create: (_) =>
            NotificationsProvider(service: MockNotificationService()),
      ),
      ChangeNotifierProvider(create: (_) => ProTeamProvider()),
    ],
    routerConfig: GoRouter(
      initialLocation: '/pro/dashboard',
      routes: [
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, _) => const DashboardScreen(),
        ),
      ],
    ),
  );

  /// Signed in, then the app started on that session — in REAL async: the
  /// mocks' delays never complete in the test's fake clock.
  Future<ProAuthProvider> started(WidgetTester tester) async {
    late ProAuthProvider p;
    await tester.runAsync(() async {
      await auth.requestProviderEmailOtp(_owner);
      final res = await auth.verifyProviderEmailOtp(
        _owner,
        MockAuthService.demoOtp,
      );
      expect(res.signedIn, isTrue);
      p = ProAuthProvider();
      await p.ready;
    });
    return p;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump();
  }

  /// The card's subtitle, read where the card is.
  Finder subtitle(String words) => find.descendant(
    of: find.ancestor(
      of: find.text('Configurer mon profil'),
      matching: find.byType(ListTile),
    ),
    matching: find.text(words),
  );

  for (final (name, seed, words) in <(String, void Function(), String)>[
    ('live', () {}, SalonValidationCopy.homeLive),
    (
      'never asked',
      () => MockData.seedNeverAsked(_p1),
      SalonValidationCopy.homeSetUp,
    ),
    (
      'pending',
      () => MockData.seedPendingRequest(_p1),
      SalonValidationCopy.linePending,
    ),
    (
      'approved, not yet live',
      () => MockData.seedFinishing(_p1),
      SalonValidationCopy.linePending,
    ),
    (
      'refused',
      () => MockData.seedRefused(_p1, code: 'photos'),
      SalonValidationCopy.lineRefused,
    ),
    (
      'refused for good',
      () => MockData.seedRefused(_p1, code: 'test_salon'),
      SalonValidationCopy.lineRefused,
    ),
    (
      'no longer online, offer lapsed',
      () => MockData.seedOffline(_p1),
      SalonValidationCopy.lineOffline,
    ),
    (
      'no longer online, offer live',
      () {
        MockData.seedOffline(_p1);
        subs.startTrialIfAbsent(_p1, tier: SalonTier.pro);
      },
      SalonValidationCopy.lineOffline,
    ),
    (
      'suspended',
      () => MockData.seedSuspended(_p1),
      SalonValidationCopy.lineSuspended,
    ),
  ]) {
    testWidgets('$name: « $words »', (tester) async {
      seed();
      final authProvider = await started(tester);
      await tester.pumpWidget(app(authProvider));
      await settle(tester);

      expect(subtitle(words), findsOneWidget);
    });
  }

  testWidgets('a server from before B0.18 (no validation key): today\'s '
      '« Complétez les étapes pour aller en ligne », even live', (
    tester,
  ) async {
    pro.legacyServer = true;
    final authProvider = await started(tester);
    await tester.pumpWidget(app(authProvider));
    await settle(tester);

    expect(subtitle(SalonValidationCopy.homeSetUp), findsOneWidget);
    expect(find.text(SalonValidationCopy.homeLive), findsNothing);
  });

  testWidgets('an offline cold start knows no state: the card keeps today\'s '
      'words — never a state the session cached (§6.2)', (tester) async {
    MockData.seedPendingRequest(_p1);
    final first = await started(tester); // the session, cached
    expect(first.salonGoLiveState?.name, 'pending');
    pro.meFails = true;
    late ProAuthProvider restarted;
    await tester.runAsync(() async {
      restarted = ProAuthProvider(); // the same stored session, offline
      await restarted.ready;
    });
    expect(restarted.isAuthenticated, isTrue);
    expect(restarted.salonGoLiveState, isNull);

    await tester.pumpWidget(app(restarted));
    await settle(tester);

    expect(subtitle(SalonValidationCopy.homeSetUp), findsOneWidget);
    expect(find.text(SalonValidationCopy.linePending), findsNothing);
  });
}
