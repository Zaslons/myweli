import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

class _MockNotificationService extends Mock
    implements NotificationServiceInterface {}

/// The dashboard bell (docs/design/push-notifications-fcm.md §10): dead until
/// now — it opens the salon's notification centre and carries the unread
/// badge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = MockAuthService();
  late _MockNotificationService notifications;

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    // Already asked → the first-visit push rationale sheet stays down, so it
    // can't sit over the bell we're tapping (PushRegistration.maybePromptOnce).
    SharedPreferences.setMockInitialValues({'myweli_push_asked': true});
    serviceLocator.authService = auth;
    serviceLocator.proService = MockProService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    notifications = _MockNotificationService();
    await auth.logoutProvider();
  });

  AppNotification note(String id, {bool read = false}) => AppNotification(
        id: id,
        type: AppNotificationType.general,
        title: 'Nouvelle réservation',
        body: 'Nouvelle demande de réservation.',
        createdAt: DateTime(2026, 6, 28),
        read: read,
      );

  Future<ProAuthProvider> signedIn(WidgetTester tester) async {
    late ProAuthProvider authProvider;
    await tester.runAsync(() async {
      await auth.requestProviderEmailOtp('jean@salon-excellence.test');
      await auth.verifyProviderEmailOtp(
        'jean@salon-excellence.test',
        MockAuthService.demoOtp,
      );
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

  Future<void> pumpDashboard(
    WidgetTester tester,
    ProAuthProvider authProvider,
    List<String> pushedRoutes,
  ) async {
    final router = GoRouter(
      initialLocation: '/pro/dashboard',
      routes: [
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, __) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/pro/notifications',
          builder: (_, __) {
            pushedRoutes.add('/pro/notifications');
            return const Scaffold(body: Text('centre'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
          ChangeNotifierProvider(
            create: (_) => NotificationsProvider(service: notifications),
          ),
        ],
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing unread → a bare bell, no badge', (tester) async {
    when(() => notifications.getNotifications()).thenAnswer(
      (_) async => ApiResponse.success([note('n1', read: true)]),
    );

    final authProvider = await signedIn(tester);
    await pumpDashboard(tester, authProvider, []);

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('unread rows → the badge shows the count', (tester) async {
    when(() => notifications.getNotifications()).thenAnswer(
      (_) async => ApiResponse.success([note('n1'), note('n2')]),
    );

    final authProvider = await signedIn(tester);
    await pumpDashboard(tester, authProvider, []);

    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping the bell opens the salon’s notification centre',
      (tester) async {
    when(() => notifications.getNotifications())
        .thenAnswer((_) async => ApiResponse.success([]));

    final pushed = <String>[];
    final authProvider = await signedIn(tester);
    await pumpDashboard(tester, authProvider, pushed);

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    expect(pushed, ['/pro/notifications']);
  });
}
