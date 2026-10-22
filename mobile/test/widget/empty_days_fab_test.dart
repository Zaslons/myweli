import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/screens/provider/appointments/appointment_list_screen.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:myweli/widgets/common/empty_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// A salon with nothing booked, any day.
class _EmptyPro extends MockProService {
  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async => ApiResponse.success(const <Appointment>[]);

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async => ApiResponse.success(
    const JournalDay(date: '2026-03-11', artists: [], appointments: []),
  );
}

/// docs/design/pro-app-batch7.md §2.4 (B7.4, decision 25) — the empty days,
/// on a real 360 × 780 phone at 200 % text, WITH their floating button:
/// - the Calendrier and the Liste use the house `EmptyState`;
/// - « Ma journée » offers one control — the floating « Nouveau »;
/// - the three floating buttons say « Nouveau »;
/// - the last line of each empty day can scroll clear of the button
///   (`AppTheme.fabClearance`) — SYSTEM §21 rows 80–81.
void main() {
  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    stubSecureStorage();
    SharedPreferences.setMockInitialValues({});
    // By hand, not `setupDependencyInjection()`: its services are `late
    // final`, and this world's pro service is the empty one.
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = _EmptyPro();
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  tearDownAll(AppClock.restore);
  setUp(() => freezeClock(kFixedNow));

  /// Scrolls [lastLine]'s page to its end, then says whether the line clears
  /// the floating button.
  Future<void> expectClearsTheFab(
    WidgetTester tester,
    Finder lastLine,
    String at,
  ) async {
    final page = find
        .ancestor(of: lastLine, matching: find.byType(Scrollable))
        .first;
    await tester.drag(page, const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final line = tester.getRect(lastLine);
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(
      line.bottom,
      lessThanOrEqualTo(fab.top),
      reason: 'the last line of $at hides under the floating button',
    );
  }

  Future<void> pumpAppointments(WidgetTester tester) async {
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProAppointmentProvider()),
        ],
        home: const AppointmentListScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  testWidgets('Calendrier: the house EmptyState, clear of « Nouveau »', (
    tester,
  ) async {
    pinSurface(tester, size: kFloorPhone, scale: 2.0);
    await pumpAppointments(tester);

    expect(find.byType(EmptyState), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Nouveau'),
      findsOneWidget,
    );
    await expectClearsTheFab(
      tester,
      find.textContaining('pour '),
      'the empty Calendrier day',
    );
  });

  testWidgets('Liste: the house EmptyState, refreshable, clear of the button', (
    tester,
  ) async {
    pinSurface(tester, size: kFloorPhone, scale: 2.0);
    await pumpAppointments(tester);
    await tester.tap(find.text('Liste'));
    await settleMocks(tester, rounds: 3);

    final empty = find.byType(EmptyState);
    expect(empty, findsOneWidget);
    // Pull-to-refresh needs something to pull: a scroll view under it.
    expect(
      find.ancestor(of: empty, matching: find.byType(Scrollable)),
      findsWidgets,
    );
    await expectClearsTheFab(
      tester,
      find.descendant(of: empty, matching: find.text('Aucun rendez-vous')),
      'the empty Liste',
    );
  });

  testWidgets('« Ma journée »: ONE control — the floating « Nouveau » — and '
      'the empty day clears it', (tester) async {
    pinSurface(tester, size: kFloorPhone, scale: 2.0);
    final router = GoRouter(
      initialLocation: '/pro/journal',
      routes: [
        GoRoute(
          path: '/pro/journal',
          builder: (_, _) => const ProJournalScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => ProAuthProvider()),
          ChangeNotifierProvider(create: (_) => ProJournalProvider()),
        ],
        routerConfig: router,
      ),
    );
    await settleMocks(tester, rounds: 4);

    expect(find.text('Aucun rendez-vous ce jour'), findsOneWidget);
    expect(find.text('+ Nouvelle réservation'), findsNothing);
    expect(
      find.widgetWithText(FloatingActionButton, 'Nouveau'),
      findsOneWidget,
    );
    await expectClearsTheFab(
      tester,
      find.text('Aucun rendez-vous ce jour'),
      'the empty « Ma journée »',
    );
  });
}
