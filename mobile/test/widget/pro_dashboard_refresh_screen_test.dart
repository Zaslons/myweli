import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/empty_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// « Accueil » (docs/design/app-pro-home-journal-fresh.md §2.2–§2.3, owner
/// decision 9 and the words of §9): an error is never a dead end, and the pull
/// always asks the server — when it fails, the figures stay and the reason is
/// said.
class _Figures extends MockProService {
  int pending = 4;
  int calls = 0;

  /// null = figures; 'network' = nothing answered; 'error' = a refusal whose
  /// own text must never reach the screen.
  String? failure;

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    String providerId,
  ) async {
    calls++;
    if (failure == 'network') {
      return ApiResponse.error('Pas de connexion. Réessayez.', code: 'network');
    }
    if (failure == 'error') return ApiResponse.error('Server exploded: 500');
    return ApiResponse.success(
      DashboardStats(
        todayAppointments: 2,
        pendingRequests: pending,
        totalAppointments: 2,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final figures = _Figures();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    // A returning salon: the first-visit « Activer les notifications » sheet
    // (`PushRegistration.maybePromptOnce`) was already answered — otherwise it
    // covers « Accueil » and swallows the taps under test.
    SharedPreferences.setMockInitialValues({'myweli_push_asked': true});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = figures; // late final — one fake for the file
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() {
    figures
      ..pending = 4
      ..calls = 0
      ..failure = null;
  });

  Future<void> openHome(WidgetTester tester) async {
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
          ChangeNotifierProvider(
            create: (_) =>
                NotificationsProvider(service: MockNotificationService()),
          ),
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
      ),
    );
    await settleMocks(tester);
  }

  /// What a pull runs: the screen's own `onRefresh`.
  Future<void> pull(WidgetTester tester) async {
    final refresh = tester.widget<BrandRefresh>(
      find.byType(BrandRefresh).first,
    );
    final done = refresh.onRefresh();
    await settleMocks(tester);
    await done;
    await settleMocks(tester);
  }

  Finder pendingFigure(int n) => find.text('$n');

  group('the error state (no figures)', () {
    testWidgets(
      'nothing answered: « Une erreur est survenue », « Pas de connexion. '
      'Réessayez. », « Réessayer » — and « Réessayer » works',
      (tester) async {
        figures.failure = 'network';
        await openHome(tester);
        expect(find.text('Une erreur est survenue'), findsOneWidget);
        expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
        expect(find.byType(EmptyState), findsOneWidget);
        figures.failure = null;
        await tester.tap(find.text('Réessayer'));
        await settleMocks(tester);
        expect(find.text('Demandes'), findsOneWidget);
        expect(pendingFigure(4), findsOneWidget);
      },
    );

    testWidgets(
      'a refusal: the title and « Réessayer » — never the server’s own text',
      (tester) async {
        figures.failure = 'error';
        await openHome(tester);
        expect(find.text('Une erreur est survenue'), findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
        expect(find.textContaining('Server exploded'), findsNothing);
        expect(find.text('Pas de connexion. Réessayez.'), findsNothing);
      },
    );

    testWidgets(
      'it can be pulled too: it sits in « Accueil »’s pull-to-refresh',
      (tester) async {
        figures.failure = 'network';
        await openHome(tester);
        expect(
          find.ancestor(
            of: find.byType(EmptyState),
            matching: find.byType(BrandRefresh),
          ),
          findsOneWidget,
        );
        final before = figures.calls;
        figures.failure = null;
        await pull(tester);
        expect(figures.calls, before + 1);
        expect(find.text('Demandes'), findsOneWidget);
      },
    );
  });

  group('the pull with figures on screen', () {
    testWidgets(
      'it asks the server, and the new figures replace the old ones',
      (tester) async {
        await openHome(tester);
        expect(pendingFigure(4), findsOneWidget);
        figures.pending = 1;
        await pull(tester);
        expect(figures.calls, 2);
        expect(pendingFigure(1), findsOneWidget);
      },
    );

    testWidgets(
      'it fails: the figures STAY and « Pas de connexion. Réessayez. » is said',
      (tester) async {
        await openHome(tester);
        figures.failure = 'network';
        await pull(tester);
        expect(pendingFigure(4), findsOneWidget);
        expect(find.text('Une erreur est survenue'), findsNothing);
        expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
      },
    );

    testWidgets(
      'a refusal: the figures stay, « Une erreur est survenue. Réessayez. »',
      (tester) async {
        await openHome(tester);
        figures.failure = 'error';
        await pull(tester);
        expect(pendingFigure(4), findsOneWidget);
        expect(
          find.text('Une erreur est survenue. Réessayez.'),
          findsOneWidget,
        );
        expect(find.textContaining('Server exploded'), findsNothing);
      },
    );
  });
}
