import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/screens/provider/appointments/appointment_list_screen.dart';
import 'package:myweli/screens/provider/appointments/pro_appointment_detail_screen.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// Each booking's amount is in the currency the booking was made in, on every
/// Pro screen that shows ONE booking (docs/design/appointment-currency-stamp.md
/// §5.3, decision 189, B14.3).
///
/// The server stores each booking's `currency` since migration 0047 (B14.1).
/// These screens read the salon's CURRENT currency instead, so the day a salon
/// changes currency its past bookings would be re-priced in the new one.
///
/// **`EUR`, never `XAF`.** The signed-in salon is XOF, and the formatter prints
/// « FCFA » for both XOF and XAF: an XAF stamp would render the same text
/// either way and prove nothing.
class _StampedPro extends MockProService {
  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    SalonId providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async => ApiResponse.success([_stamped]);

  @override
  Future<ApiResponse<EarningsData>> getEarnings(
    SalonId providerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async => ApiResponse.success(
    // Through `fromJson`, as the API service builds it: the row's own
    // `currency` is what the server sends (provider_earnings_service.dart).
    EarningsData.fromJson({
      'totalEarnings': 15000,
      'currency': 'XOF',
      'transactions': [
        {
          'id': 'transaction_a_eur',
          'appointmentId': 'a_eur',
          'amount': 15000,
          'currency': 'EUR',
          'date': kFixedNow.toIso8601String(),
          'status': 'completed',
        },
      ],
    }),
  );
}

/// An amount as the app prints it in EUR (the thousands separator is U+202F,
/// so a typed literal would never match).
String _eur(double amount) =>
    Formatters.formatCurrency(amount, currency: 'EUR');

/// The amount's digits alone — currency-blind. The control each test checks
/// first: the booking IS on screen, so a missing « EUR » can only mean the
/// wrong currency, never a row that was not rendered.
final String _digits15000 = _eur(15000).split(' ').first;

/// Today (the frozen clock), confirmed, made in EUR at an XOF salon.
final Appointment _stamped = Appointment(
  id: 'a_eur',
  userId: 'manual',
  providerId: SalonId('provider1'),
  serviceIds: const ['service1'],
  appointmentDate: kFixedNow.add(const Duration(hours: 1)),
  status: AppointmentStatus.confirmed,
  totalPrice: 15000,
  depositAmount: 4500,
  balanceDue: 10500,
  clientName: 'Awa',
  currency: 'EUR',
  createdAt: kFixedNow,
);

void main() {
  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    stubSecureStorage();
    SharedPreferences.setMockInitialValues({});
    // By hand, not `setupDependencyInjection()`: its services are `late
    // final`, and this world's pro service is the stamped one.
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = _StampedPro();
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  tearDownAll(AppClock.restore);
  setUp(() => freezeClock(kFixedNow));

  /// The control every test needs: the signed-in salon really is XOF, so an
  /// amount in EUR can only have come from the booking.
  void expectSalonIsXof(ProAuthProvider auth) => expect(
    auth.salonCurrency,
    'XOF',
    reason: 'the control: the salon is XOF, the booking EUR',
  );

  Future<ProAuthProvider> pumpList(WidgetTester tester) async {
    final auth = await signInPro(tester);
    expectSalonIsXof(auth);
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
    return auth;
  }

  testWidgets('Calendrier: the day’s booking is in its own currency', (
    tester,
  ) async {
    await pumpList(tester);
    expect(
      find.textContaining(_digits15000),
      findsWidgets,
      reason: 'the control: the booking’s amount is on screen',
    );
    expect(
      find.textContaining('EUR'),
      findsWidgets,
      reason: 'the calendar’s day list prices the booking in EUR',
    );
  });

  testWidgets('Liste: the booking is in its own currency', (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('Liste'));
    await settleMocks(tester, rounds: 3);
    await tester.tap(find.text('Tous'));
    await settleMocks(tester, rounds: 3);
    expect(
      find.textContaining(_digits15000),
      findsWidgets,
      reason: 'the control: the booking’s amount is on screen',
    );
    expect(
      find.textContaining('EUR'),
      findsWidgets,
      reason: 'the list row prices the booking in EUR',
    );
  });

  testWidgets('the booking’s detail: the total and the announced deposit are '
      'in its own currency', (tester) async {
    final auth = await signInPro(tester);
    expectSalonIsXof(auth);
    final appointments = ProAppointmentProvider();
    await tester.runAsync(
      () => appointments.loadAppointments(SalonId('provider1')),
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider.value(value: appointments),
          ChangeNotifierProvider(create: (_) => ProJournalProvider()),
        ],
        home: const ProAppointmentDetailScreen(appointmentId: 'a_eur'),
      ),
    );
    await settleMocks(tester, rounds: 3);
    expect(
      find.textContaining(_digits15000),
      findsWidgets,
      reason: 'the control: the booking’s total is on screen',
    );
    expect(find.text(_eur(15000)), findsOneWidget, reason: 'the total');
    expect(
      find.text('Acompte annoncé : ${_eur(4500)}'),
      findsOneWidget,
      reason: 'the deposit',
    );
  });

  testWidgets('Revenus: each row is in its own currency', (tester) async {
    final auth = await signInPro(tester);
    expectSalonIsXof(auth);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProEarningsProvider()),
        ],
        home: const EarningsScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
    expect(
      find.textContaining(_digits15000),
      findsNWidgets(2),
      reason: 'the control: the total AND the row are on screen',
    );
    expect(
      find.text(_eur(15000)),
      findsOneWidget,
      reason: 'the row is EUR; the total above it stays in the salon’s',
    );
  });
}
