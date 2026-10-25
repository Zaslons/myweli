import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/account_scope.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/main_pro.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_availability_provider.dart';
import 'package:myweli/providers/pro_before_after_provider.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/providers/pro_gallery_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_kyc_provider.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/providers/pro_salon_profile_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';
import 'package:myweli/services/mock/mock_pro_kyc_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:myweli/widgets/common/session_ended_notice.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/surface.dart';

/// The salon's figures, held while [gate] is set — « before the
/// receptionist's own answer » is a state the test can stand in.
class _HeldFigures extends MockProService {
  Completer<void>? gate;

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    String providerId,
  ) async {
    final hold = gate;
    if (hold != null) await hold.future;
    return super.getDashboardStats(providerId);
  }
}

/// The bell's feed, held the same way.
class _HeldFeed extends MockNotificationService {
  Completer<void>? gate;

  @override
  Future<ApiResponse<List<AppNotification>>> getNotifications() async {
    final hold = gate;
    if (hold != null) await hold.future;
    return super.getNotifications();
  }
}

const _owner = 'jean@salon-excellence.test';
// The same salon, without `finances.view`: the server never sends her money.
const _reception = 'fatou.reception@myweli.test';

/// docs/design/pro-account-scope.md §1, §6 — found by a probe on the real
/// code: the receptionist who signed in after the owner saw the owner's two
/// « Revenus prévus » cards, at every frame, and nothing ever re-read them.
void main() {
  final auth = MockAuthService();
  final figures = _HeldFigures();
  final feed = _HeldFeed();
  final subscriptions = MockSubscriptionService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator
      ..authService = auth
      ..proService = figures
      ..proNotificationService = feed
      // Every store the wiring test builds reads its service at
      // construction.
      ..proArtistService = MockProArtistService()
      ..proClientsService = MockProClientsService()
      ..proKycService = MockProKycService()
      ..subscriptionService = subscriptions
      ..proTeamService = MockProTeamService(subscriptions: subscriptions)
      ..imageUploadService = MockImageUploadService()
      ..logoImageUploadService = MockImageUploadService()
      ..providerService = MockProviderService()
      ..localityService = MockLocalityService()
      ..proPushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });

  setUp(() async {
    // The stores of the previous test were disposed with its tree.
    ProSalonScope.clear();
    AccountScope.clear();
    MockData.resetTeam();
    figures.gate = null;
    feed.gate = null;
    await auth.logoutProvider();
  });

  GoRouter appRouter(String initial) => GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/pro/login', builder: (_, _) => const ProLoginScreen()),
      GoRoute(
        path: '/pro/dashboard',
        builder: (_, _) => const DashboardScreen(),
      ),
    ],
  );

  /// The e-mail sign-in, in real time: the mocks' delays only complete
  /// there, and the membership refresh must land before a screen mounts.
  Future<void> signIn(
    WidgetTester tester,
    ProAuthProvider pro,
    String email,
  ) async {
    await tester.runAsync(() async {
      await pro.requestEmailOtp(email);
      expect(
        await pro.verifyEmailOtp(email, MockAuthService.demoOtp),
        isTrue,
        reason: 'the mock refused $email: ${pro.error}',
      );
      for (var i = 0; i < 60 && pro.membership == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(pro.membership, isNotNull, reason: 'no membership for $email');
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// A signed-in owner on her dashboard, the app's real stores under it.
  Future<(ProAuthProvider, GoRouter)> ownerOnHerDashboard(
    WidgetTester tester,
  ) async {
    pinSurface(tester, size: const Size(800, 3000));
    final router = appRouter('/pro/dashboard');
    late ProAuthProvider pro;
    await tester.runAsync(() async {
      pro = ProAuthProvider(router: router);
      await pro.ready;
    });
    await signIn(tester, pro, _owner);
    await tester.pumpWidget(
      wrapApp(routerConfig: router, providers: proAppProviders(pro)),
    );
    await settle(tester);
    // The control for every check below: the owner DOES see her money and
    // her bell.
    expect(find.text('Revenus prévus'), findsWidgets);
    expect(find.byType(Badge), findsOneWidget);
    return (pro, router);
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('the receptionist never sees the owner\'s revenue, nor her '
      'bell — not while her own reads are out', (tester) async {
    final (pro, router) = await ownerOnHerDashboard(tester);

    // « Déconnexion » — what the Profile's button does (pro_profile_screen).
    await tester.runAsync(pro.logout);
    router.go('/pro/login');
    await settle(tester);

    final release = Completer<void>();
    figures.gate = release;
    feed.gate = release;
    await signIn(tester, pro, _reception);
    router.go('/pro/dashboard');

    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Revenus prévus'),
        findsNothing,
        reason: 'frame $frame: the receptionist is shown the owner\'s revenue',
      );
      expect(
        find.byType(Badge),
        findsNothing,
        reason: 'frame $frame: the receptionist is shown the owner\'s bell',
      );
    }

    release.complete();
    await settle(tester);
    expect(
      find.text('Revenus prévus'),
      findsNothing,
      reason: 'her own figures carry no money',
    );
  });

  group('the Pro session refused by the server (§2.3, Q2 = a)', () {
    testWidgets('the sign-in, with the sentence, and nothing of the salon', (
      tester,
    ) async {
      final (pro, router) = await ownerOnHerDashboard(tester);

      await tester.runAsync(() async {
        await auth.expireProviderSession();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settle(tester);

      expect(pro.isAuthenticated, isFalse);
      expect(location(router), '/pro/login');
      expect(find.text(kSessionEndedMessage), findsOneWidget);
      expect(find.text('Revenus prévus'), findsNothing);
    });

    testWidgets('« Déconnexion » says nothing of a session', (tester) async {
      final (pro, router) = await ownerOnHerDashboard(tester);

      await tester.runAsync(pro.logout);
      router.go('/pro/login');
      await settle(tester);

      expect(find.text(kSessionEndedMessage), findsNothing);
    });
  });

  // §6 « Le câblage »: the stores the Pro app RUNS are the ones reset — read
  // off the production list, not a copy of it.
  testWidgets('every Pro store is tracked by its scope; the public ones are '
      'not', (tester) async {
    ProSalonScope.clear();
    AccountScope.clear();
    late ProAuthProvider pro;
    await tester.runAsync(() async {
      pro = ProAuthProvider(router: appRouter('/pro/login'));
      await pro.ready;
    });
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: proAppProviders(pro),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final salonStores = <Object>[
      context.read<ProDashboardProvider>(),
      context.read<ProAppointmentProvider>(),
      context.read<ProServiceProvider>(),
      context.read<ProArtistProvider>(),
      context.read<ProClientsProvider>(),
      context.read<ProJournalProvider>(),
      context.read<ProAvailabilityProvider>(),
      context.read<ProEarningsProvider>(),
      context.read<ProReviewsProvider>(),
      context.read<ProSalonProfileProvider>(),
      context.read<ProDepositSettingsProvider>(),
      context.read<ProOnboardingProvider>(),
      context.read<ProGalleryProvider>(),
      context.read<ProBeforeAfterProvider>(),
      context.read<ProSubscriptionProvider>(),
      context.read<ProTeamProvider>(),
    ];
    for (final store in salonStores) {
      expect(
        ProSalonScope.isTracked(store),
        isTrue,
        reason: '${store.runtimeType} keeps the previous salon',
      );
    }
    for (final store in <Object>[
      context.read<NotificationsProvider>(),
      context.read<ProKycProvider>(),
    ]) {
      expect(
        AccountScope.isTracked(store),
        isTrue,
        reason: '${store.runtimeType} keeps the previous account',
      );
    }
    for (final public in <Object>[
      context.read<ProviderProvider>(),
      context.read<LocalityProvider>(),
    ]) {
      expect(AccountScope.isTracked(public), isFalse);
    }
    await tester.pump(const Duration(milliseconds: 100));
  });
}
