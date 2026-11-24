import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/auth/open_sign_in.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/appointments/my_bookings_screen.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/notifications/notifications_screen.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/common/account_loader.dart';
import 'package:myweli/widgets/notifications/mark_all_read_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

class _Bookings extends Mock implements AppointmentServiceInterface {}

class _Notifications extends Mock implements NotificationServiceInterface {}

/// consumer-signin-push.md §2.5 (decision 207) and §2.3: « Rendez-vous » and
/// « Actu » draw a signed-out page; signing in from them loads the account —
/// from the root (`AccountLoader`), on a screen that was not built again.
void main() {
  final bookings = _Bookings();
  final notifications = _Notifications();
  final auth = _Auth();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator
      ..authService = auth
      ..appointmentService = bookings
      ..notificationService = notifications
      ..favoritesService = MockFavoritesService()
      ..providerService = MockProviderService()
      ..localityService = MockLocalityService();
  });

  setUp(() {
    reset(bookings);
    reset(notifications);
    when(
      () => bookings.getUserAppointments(status: any(named: 'status')),
    ).thenAnswer(
      (_) async => ApiResponse.success([
        Appointment(
          id: 'a1',
          userId: 'u-phone',
          providerId: const SalonId('provider1'),
          serviceIds: const ['s1'],
          appointmentDate: AppClock.now().add(const Duration(days: 2)),
          status: AppointmentStatus.confirmed,
          totalPrice: 20000,
          createdAt: DateTime(2026),
          providerName: 'Salon Awa',
        ),
      ]),
    );
    when(
      () => notifications.getNotifications(),
    ).thenAnswer((_) async => ApiResponse.success(const []));
  });
  tearDown(SignInGate.reset);

  late AuthProvider authProvider;

  Widget app(String initial) {
    authProvider = AuthProvider();
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('ACCUEIL')),
        GoRoute(path: '/bookings', builder: (_, _) => const MyBookingsScreen()),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => LoginScreen(
            reason: SignInReason.fromKey(state.uri.queryParameters['reason']),
          ),
        ),
      ],
    );
    return wrapApp(
      routerConfig: router,
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(
          create: (_) => NotificationsProvider(service: notifications),
        ),
      ],
      // What the app's root installs above every route (main.dart).
      builder: (_, child) => AccountLoader(child: child!),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  group('« Rendez-vous »', () {
    testWidgets('a guest stays, and reads what the tab is for — no redirect, '
        'no tab bar that would sort nothing', (tester) async {
      await tester.pumpWidget(app('/bookings'));
      await settle(tester);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Vos rendez-vous'), findsOneWidget);
      expect(
        find.text(
          'Connectez-vous pour retrouver vos rendez-vous et en suivre l’état.',
        ),
        findsOneWidget,
      );
      expect(find.text('À venir'), findsNothing);
      verifyNever(
        () => bookings.getUserAppointments(status: any(named: 'status')),
      );
    });

    testWidgets('« Se connecter » opens the sign-in over it; signed in, the '
        'bookings load from the root and the tabs appear', (tester) async {
      await tester.pumpWidget(app('/bookings'));
      await settle(tester);
      await tester.tap(find.text('Se connecter'));
      await settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('Connectez-vous pour retrouver vos rendez-vous.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('À venir'), findsOneWidget);
      expect(find.text('Salon Awa'), findsOneWidget);
    });

    testWidgets('closed: the signed-out page again', (tester) async {
      await tester.pumpWidget(app('/bookings'));
      await settle(tester);
      await tester.tap(find.text('Se connecter'));
      await settle(tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settle(tester);
      expect(find.text('Vos rendez-vous'), findsOneWidget);
    });
  });

  group('« Actu »', () {
    testWidgets('a guest reads a signed-out page — not an error whose retry '
        'cannot work — and no « Tout marquer comme lu »', (tester) async {
      await tester.pumpWidget(app('/notifications'));
      await settle(tester);
      expect(find.text('Vos notifications'), findsOneWidget);
      expect(
        find.text(
          'Connectez-vous pour suivre vos rendez-vous et les réponses des '
          'salons.',
        ),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsNothing);
      expect(find.text('Chargement impossible'), findsNothing);
      // By type: the button also hides itself at 0 unread, which a guest
      // always has — its tooltip's absence proved nothing.
      expect(find.byType(MarkAllReadButton), findsNothing);
      verifyNever(() => notifications.getNotifications());
    });

    testWidgets('signed in from it: the feed loads', (tester) async {
      await tester.pumpWidget(app('/notifications'));
      await settle(tester);
      await tester.tap(find.text('Se connecter'));
      await settle(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(find.text('Vos notifications'), findsNothing);
      verify(() => notifications.getNotifications()).called(greaterThan(0));
    });
  });
}

class _Auth extends MockAuthService {
  @override
  Future<ApiResponse<User>> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ApiResponse.success(
      User(
        id: 'u-phone',
        email: 'awa@test.com',
        phoneNumber: '+2250700000001',
        authProvider: 'google',
        createdAt: DateTime(2026),
      ),
    );
  }
}
