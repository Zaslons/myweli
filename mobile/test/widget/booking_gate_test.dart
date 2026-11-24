import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/auth/open_sign_in.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/messaging_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/booking/booking_confirmation_screen.dart';
import 'package:myweli/screens/booking/booking_hub_screen.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/booking/slot_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/surface.dart';

/// consumer-signin-push.md §2.4 (decision 204): the booking's sign-in is at
/// the hub's « Confirmer », before the confirmation opens — as on the website.
/// « Fermer » leaves the person on the hub with their choice; signed in, the
/// confirmation opens with it.
void main() {
  final auth = _Auth();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator
      ..authService = auth
      ..providerService = MockProviderService()
      ..appointmentService = MockAppointmentService()
      ..localityService = MockLocalityService();
  });
  tearDown(SignInGate.reset);

  final salon = MockData.providers[0];
  final slot = DateTime.now().add(const Duration(days: 3));

  late GoRouter router;
  late AuthProvider authProvider;

  Widget app({required String initial}) {
    authProvider = AuthProvider();
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/hub',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(
                Uri(
                  path: '/booking/confirm',
                  queryParameters: {
                    'providerId': salon.id.value,
                    'serviceIds': salon.services.first.id,
                    'dateTime': slot.toIso8601String(),
                  },
                ).toString(),
              ),
              child: const Text('HUB'),
            ),
          ),
        ),
        GoRoute(
          path: '/booking',
          builder: (_, _) => BookingHubScreen(
            providerId: salon.id,
            initialServiceIds: [salon.services.first.id],
          ),
        ),
        GoRoute(
          path: '/booking/confirm',
          builder: (_, state) {
            final q = state.uri.queryParameters;
            if (q['real'] == null && initial == '/booking') {
              return const Scaffold(body: Text('CONFIRMATION'));
            }
            return BookingConfirmationScreen(
              providerId: salon.id,
              serviceIds: q['serviceIds']!.split(','),
              appointmentDateTime: DateTime.parse(q['dateTime']!),
            );
          },
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
        ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
      ],
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> pickAndConfirm(WidgetTester tester) async {
    // What a tap on a slot does.
    tester.widget<SlotPicker>(find.byType(SlotPicker)).onSlotSelected(slot);
    await settle(tester);
    await tester.ensureVisible(find.text('Confirmer'));
    await tester.tap(find.text('Confirmer'));
    await settle(tester);
  }

  group('the hub', () {
    testWidgets('a guest: the sign-in opens at « Confirmer », with its reason; '
        '« Fermer » leaves them on the hub, nothing opened', (tester) async {
      pinSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(app(initial: '/booking'));
      await settle(tester);
      await pickAndConfirm(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('Connectez-vous pour confirmer votre réservation.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Fermer'));
      await settle(tester);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(BookingHubScreen), findsOneWidget);
      expect(find.text('CONFIRMATION'), findsNothing);
    });

    testWidgets('signed in there: the confirmation opens, over the hub', (
      tester,
    ) async {
      pinSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(app(initial: '/booking'));
      await settle(tester);
      await pickAndConfirm(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);

      expect(find.text('CONFIRMATION'), findsOneWidget);
      router.pop();
      await settle(tester);
      expect(find.byType(BookingHubScreen), findsOneWidget);
    });
  });

  testWidgets('the confirmation reached signed out anyway: the sign-in opens '
      'over it, and « Fermer » closes both — back where the person came from', (
    tester,
  ) async {
    pinSurface(tester, size: const Size(400, 2400));
    await tester.pumpWidget(app(initial: '/hub'));
    await settle(tester);
    await tester.tap(find.text('HUB'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Fermer'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(BookingConfirmationScreen), findsNothing);
    expect(find.text('HUB'), findsOneWidget);
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
