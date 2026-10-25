import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/account_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/app_router.dart';
import 'package:myweli/main.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/messaging_provider.dart';
import 'package:myweli/providers/notification_preferences_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/appointments/appointment_detail_screen.dart';
import 'package:myweli/screens/appointments/my_bookings_screen.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/screens/profile/profile_screen.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_messaging_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_review_service.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/booking/compact_appointment_tile.dart';
import 'package:myweli/widgets/common/app_async_view.dart';
import 'package:myweli/widgets/common/session_ended_notice.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/surface.dart';

/// Every read of the account's bookings waits for the test to answer it —
/// so « before B's answer » is a state the test can stand in, frame by frame.
class _HeldAppointments extends MockAppointmentService {
  final lists = <Completer<ApiResponse<List<Appointment>>>>[];
  final details = <Completer<ApiResponse<Appointment>>>[];

  @override
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  }) {
    final read = Completer<ApiResponse<List<Appointment>>>();
    lists.add(read);
    return read.future;
  }

  @override
  Future<ApiResponse<Appointment>> getAppointmentById(String id) {
    final read = Completer<ApiResponse<Appointment>>();
    details.add(read);
    return read.future;
  }

  /// Answers every list read still out.
  void answerLists(ApiResponse<List<Appointment>> answer) {
    for (final read in lists) {
      if (!read.isCompleted) read.complete(answer);
    }
  }

  void answerDetails(ApiResponse<Appointment> answer) {
    for (final read in details) {
      if (!read.isCompleted) read.complete(answer);
    }
  }
}

Appointment _booking(String id, String userId, String salon) => Appointment(
  id: id,
  userId: userId,
  providerId: 'provider-of-$id',
  serviceIds: const ['s1'],
  // Upcoming: it is on « Mes rendez-vous »' first tab and on the home strip.
  appointmentDate: DateTime.now().add(const Duration(days: 3)),
  status: AppointmentStatus.confirmed,
  totalPrice: 20000,
  depositAmount: 0,
  balanceDue: 20000,
  createdAt: DateTime(2026, 10),
  providerName: salon,
);

/// The screens of the account, on a router of the test's own: the app's is a
/// static that starts on the splash and its 3.8 s hold.
GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, state) =>
          LoginScreen(returnTo: state.uri.queryParameters['returnTo']),
    ),
    GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/bookings', builder: (_, _) => const MyBookingsScreen()),
    GoRoute(
      path: '/appointment/:id',
      builder: (_, state) =>
          AppointmentDetailScreen(appointmentId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
  ],
);

void main() {
  late _HeldAppointments appointments;
  late MockAuthService mockAuth;

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    stubSecureStorage();
    appointments = _HeldAppointments();
    mockAuth = MockAuthService();
    serviceLocator
      ..authService = mockAuth
      ..appointmentService = appointments
      ..providerService = MockProviderService()
      ..localityService = MockLocalityService()
      ..favoritesService = MockFavoritesService()
      ..notificationService = MockNotificationService()
      ..messagingService = MockMessagingService()
      ..reviewService = MockReviewService()
      ..pushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appointments.lists.clear();
    appointments.details.clear();
  });

  /// The e-mail sign-in, as the login screen drives it.
  Future<void> signIn(
    WidgetTester tester,
    AuthProvider auth,
    String email,
  ) async {
    final sent = auth.requestEmailOtp(email);
    await tester.pump(const Duration(milliseconds: 400));
    expect(await sent, isTrue, reason: 'the mock refused to send to $email');
    final signedIn = auth.verifyEmailOtp(email, MockAuthService.demoOtp);
    await tester.pump(const Duration(milliseconds: 400));
    expect(await signedIn, isTrue, reason: 'the mock refused $email');
  }

  Iterable<String> shownBookings(WidgetTester tester) => [
    for (final card in tester.widgetList<AppointmentCard>(
      find.byType(AppointmentCard),
    ))
      card.appointment.id,
    for (final tile in tester.widgetList<CompactAppointmentTile>(
      find.byType(CompactAppointmentTile),
    ))
      tile.appointment.id,
    // The detail draws what its view is handed — and prints no salon name.
    for (final view in tester.widgetList<AppAsyncView<Appointment>>(
      find.byType(AppAsyncView<Appointment>),
    ))
      ?view.data?.id,
  ];

  /// Pumps [frames] frames and looks at EVERY one: a booking of A's shown for
  /// one frame is shown.
  Future<void> expectNothingOfA(
    WidgetTester tester, {
    required String where,
    int frames = 6,
  }) async {
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        shownBookings(tester),
        isNot(contains('rdv-a')),
        reason: '$where, frame $frame: account B is shown A\'s booking',
      );
      expect(
        find.text('Salon de A'),
        findsNothing,
        reason: '$where, frame $frame: account B is shown A\'s salon',
      );
      expect(
        find.text('Derniers rendez-vous'),
        findsNothing,
        reason: '$where, frame $frame: the home strip is A\'s',
      );
    }
  }

  // docs/design/consumer-account-scope.md §6 — the widget the brief asked for.
  testWidgets('account B never sees account A\'s booking — not while its own '
      'read is out, not when it fails', (tester) async {
    // Tall, so the home strip — below « À la une » — is built at all: a
    // check on a sliver past the cache extent passes about nothing.
    pinSurface(tester, size: const Size(800, 3000));
    final auth = AuthProvider();
    await tester.pump(const Duration(milliseconds: 100));
    await signIn(tester, auth, 'compte.a@myweli.test');

    final router = _router('/bookings');
    await tester.pumpWidget(
      wrapApp(routerConfig: router, providers: consumerAppProviders(auth)),
    );
    await tester.pump();
    appointments.answerLists(
      ApiResponse.success([_booking('rdv-a', auth.user!.id, 'Salon de A')]),
    );
    await settleMocks(tester);
    expect(shownBookings(tester), [
      'rdv-a',
    ], reason: 'the scenario: A sees their own booking');
    // The control for every check below: the home strip CAN show A's booking
    // — to A.
    router.go('/home');
    await tester.pump();
    appointments.answerLists(
      ApiResponse.success([_booking('rdv-a', auth.user!.id, 'Salon de A')]),
    );
    await settleMocks(tester);
    expect(find.text('Derniers rendez-vous'), findsOneWidget);
    expect(shownBookings(tester), contains('rdv-a'));
    // …and A opens it: the selection is app-wide and outlives the screen
    // (F1), so it is A's that B's detail of the same id must not show.
    router.go('/appointment/rdv-a');
    await tester.pump();
    appointments.answerDetails(
      ApiResponse.success(_booking('rdv-a', auth.user!.id, 'Salon de A')),
    );
    await settleMocks(tester);
    expect(shownBookings(tester), contains('rdv-a'));

    // « Déconnexion », the way a person does it.
    router.go('/profile');
    await settleMocks(tester);
    await tester.ensureVisible(find.text('Déconnexion'));
    await tester.tap(find.text('Déconnexion'));
    await tester.pump();
    await tester.tap(find.text('Se déconnecter'));
    await settleMocks(tester);
    expect(auth.isAuthenticated, isFalse, reason: 'the scenario: signed out');

    // Account B, on the same phone. None of its reads has answered.
    await signIn(tester, auth, 'compte.b@myweli.test');
    final b = auth.user!.id;

    router.go('/home');
    await expectNothingOfA(tester, where: 'Accueil');
    router.go('/bookings');
    await expectNothingOfA(tester, where: 'Mes rendez-vous');
    router.go('/appointment/rdv-a');
    await expectNothingOfA(tester, where: 'the detail of A\'s id');

    // B's reads fail: still nothing of A.
    appointments.answerLists(ApiResponse.error('Hors ligne', code: 'network'));
    appointments.answerDetails(
      ApiResponse.error('Rendez-vous introuvable.', code: 'not_found'),
    );
    await expectNothingOfA(tester, where: 'the detail, B\'s read failed');
    router.go('/bookings');
    await expectNothingOfA(tester, where: 'Mes rendez-vous, B\'s read failed');

    // B's read answers: B's own booking.
    router.go('/home');
    await tester.pump();
    appointments.answerLists(
      ApiResponse.success([_booking('rdv-b', b, 'Salon de B')]),
    );
    await settleMocks(tester);
    expect(shownBookings(tester), contains('rdv-b'));
    expect(shownBookings(tester), isNot(contains('rdv-a')));
  });

  /// A signed-in A with their booking on screen at [at], the app as it runs:
  /// the production stores, and the notice at the root.
  Future<(AuthProvider, GoRouter)> signedInAt(
    WidgetTester tester,
    String at,
  ) async {
    pinSurface(tester, size: const Size(800, 3000));
    final auth = AuthProvider();
    await tester.pump(const Duration(milliseconds: 100));
    await signIn(tester, auth, 'compte.a@myweli.test');
    final router = _router(at);
    await tester.pumpWidget(
      wrapApp(
        routerConfig: router,
        providers: consumerAppProviders(auth),
        builder: (_, child) =>
            SessionEndedNotice(router: router, child: child!),
      ),
    );
    await tester.pump();
    appointments.answerLists(
      ApiResponse.success([_booking('rdv-a', auth.user!.id, 'Salon de A')]),
    );
    await settleMocks(tester);
    expect(shownBookings(tester), contains('rdv-a'), reason: 'the scenario');
    return (auth, router);
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  group('the session refused by the server (consumer-account-scope.md §2.5, '
      'Q1 = a)', () {
    testWidgets('on a public screen: the person stays, the bar says it and '
        'offers « Se connecter »', (tester) async {
      final (auth, router) = await signedInAt(tester, '/home');

      await mockAuth.expireSession();
      await tester.pump();
      await tester.pump();

      expect(auth.isAuthenticated, isFalse);
      expect(location(router), '/home');
      expect(find.text(kSessionEndedMessage), findsOneWidget);
      await expectNothingOfA(
        tester,
        where: 'Accueil, after the end',
        frames: 2,
      );

      await tester.tap(find.widgetWithText(SnackBarAction, 'Se connecter'));
      await settleMocks(tester);
      expect(location(router), '/login?returnTo=%2Fhome');
    });

    testWidgets('on an account screen: it leaves for the sign-in, which '
        'brings the person back to it', (tester) async {
      final (auth, router) = await signedInAt(tester, '/bookings');

      await mockAuth.expireSession();
      await tester.pump();
      await settleMocks(tester);

      expect(auth.isAuthenticated, isFalse);
      expect(location(router), '/login?returnTo=%2Fbookings');
      expect(find.text(kSessionEndedMessage), findsOneWidget);
      expect(
        find.widgetWithText(SnackBarAction, 'Se connecter'),
        findsNothing,
        reason: 'the person is on the sign-in already',
      );
      await expectNothingOfA(tester, where: 'after the end', frames: 2);
    });

    testWidgets('« Déconnexion » says nothing of a session', (tester) async {
      final (_, router) = await signedInAt(tester, '/bookings');
      router.go('/profile');
      await settleMocks(tester);

      await tester.ensureVisible(find.text('Déconnexion'));
      await tester.tap(find.text('Déconnexion'));
      await tester.pump();
      await tester.tap(find.text('Se déconnecter'));
      await settleMocks(tester);

      expect(location(router), '/login');
      expect(find.text(kSessionEndedMessage), findsNothing);
    });
  });

  // §6 « Le câblage »: the stores the app RUNS are the ones reset — read off
  // the production list, not a copy of it.
  testWidgets('every account store the app mounts is tracked; the communes '
      'are not', (tester) async {
    AccountScope.clear();
    final auth = AuthProvider();
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: consumerAppProviders(auth),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final stores = <Object>[
      context.read<AppointmentProvider>(),
      context.read<NotificationsProvider>(),
      context.read<NotificationPreferencesProvider>(),
      context.read<FavoritesProvider>(),
      context.read<MessagingProvider>(),
      context.read<ProviderProvider>(),
    ];
    for (final store in stores) {
      expect(
        AccountScope.isTracked(store),
        isTrue,
        reason: '${store.runtimeType} outlives the account it was loaded for',
      );
    }
    final communes = context.read<LocalityProvider>();
    expect(AccountScope.isTracked(communes), isFalse);
    expect(communes, isNot(isA<AccountScoped>()));
    await tester.pump(const Duration(milliseconds: 100));
  });

  // A renamed route would stop leaving for the sign-in, silently: each prefix
  // must still name a path of the consumer router.
  test('every account-only prefix is a route of the app', () {
    final paths = <String>[];
    void walk(List<RouteBase> routes, String parent) {
      for (final route in routes.whereType<GoRoute>()) {
        final path = route.path.startsWith('/')
            ? route.path
            : '${parent == '/' ? '' : parent}/${route.path}';
        paths.add(path);
        walk(route.routes, path);
      }
    }

    walk(AppRouter.router.configuration.routes, '');
    for (final prefix in kAccountOnlyRoutePrefixes) {
      expect(
        paths.where((p) => p.startsWith(prefix)),
        isNotEmpty,
        reason: '« $prefix » names no route of the consumer app ($paths)',
      );
    }
    for (final account in [
      '/bookings',
      '/appointment/rdv-a',
      '/notifications',
      '/profile/edit',
      '/profile/data',
      '/profile/notifications',
      '/booking/confirm?providerId=p1',
    ]) {
      expect(isAccountOnlyRoute(account), isTrue, reason: account);
    }
    for (final public in [
      '/home',
      '/profile',
      '/booking?providerId=p1',
      '/provider/p1',
      '/providers',
      '/carte',
      '/a-propos',
    ]) {
      expect(isAccountOnlyRoute(public), isFalse, reason: public);
    }
  });
}
