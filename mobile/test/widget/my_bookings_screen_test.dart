import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/appointments/my_bookings_screen.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/booking/visit_summary.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

class _Bookings extends Mock implements AppointmentServiceInterface {}

/// « Passés » tells the truth (docs/design/consumer-app-truth.md §2.7,
/// decisions 165–167): a past booking keeps its real status, a no-show is
/// listed, and the summary counts only what the salon marked « Terminé ».
void main() {
  final bookings = _Bookings();
  var current = <Appointment>[];

  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    stubSecureStorage();
    serviceLocator
      ..authService = MockAuthService()
      ..appointmentService = bookings
      ..providerService = MockProviderService()
      ..localityService = MockLocalityService();
    when(
      () => bookings.getUserAppointments(status: any(named: 'status')),
    ).thenAnswer((_) async => ApiResponse.success(current));
  });

  tearDownAll(AppClock.restore);

  setUp(() {
    freezeClock(kFixedNow);
    SharedPreferences.setMockInitialValues({});
  });

  Appointment appt(
    String id,
    AppointmentStatus status,
    Duration fromNow, {
    double total = 20000,
  }) => Appointment(
    id: id,
    userId: 'user1',
    providerId: const SalonId('provider1'),
    serviceIds: const ['s1'],
    appointmentDate: kFixedNow.add(fromNow),
    status: status,
    totalPrice: total,
    createdAt: DateTime(2026),
    providerName: 'Salon $id',
  );

  Future<void> openPast(WidgetTester tester) async {
    // Tall enough that the lazy list builds every card.
    pinSurface(tester, size: const Size(400, 4000));
    final auth = await signInConsumer(tester);
    final router = GoRouter(
      initialLocation: '/bookings',
      routes: [
        GoRoute(path: '/bookings', builder: (_, _) => const MyBookingsScreen()),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        routerConfig: router,
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Passés'));
    await tester.pumpAndSettle();
  }

  List<String> listed(WidgetTester tester) => [
    for (final c in tester.widgetList<AppointmentCard>(
      find.byType(AppointmentCard),
    ))
      c.appointment.id,
  ];

  testWidgets('every past booking is listed with its real status', (
    tester,
  ) async {
    current = [
      appt('done', AppointmentStatus.completed, const Duration(days: -10)),
      appt('unconf', AppointmentStatus.pending, const Duration(days: -3)),
      appt('conf', AppointmentStatus.confirmed, const Duration(days: -2)),
      appt('absent', AppointmentStatus.noShow, const Duration(days: -5)),
      appt('next', AppointmentStatus.confirmed, const Duration(days: 2)),
      appt('gone', AppointmentStatus.cancelled, const Duration(days: -1)),
    ];
    await openPast(tester);

    expect(listed(tester), ['conf', 'unconf', 'absent', 'done']);
    expect(find.text('Non confirmé'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
    expect(find.text('Confirmé'), findsOneWidget);
    // Only the one the salon closed says « Terminé ».
    expect(find.text('Terminé'), findsOneWidget);

    // The summary counts that one visit, and its price only (20 000, not
    // the 80 000 of all four past bookings).
    Finder inSummary(String text) => find.descendant(
      of: find.byType(VisitSummary),
      matching: find.text(text),
    );
    expect(inSummary('1'), findsOneWidget);
    expect(inSummary('visite'), findsOneWidget);
    expect(inSummary(Formatters.formatCurrency(20000)), findsOneWidget);
  });

  testWidgets('with no visit the salon closed, there is no summary', (
    tester,
  ) async {
    current = [
      appt('unconf', AppointmentStatus.pending, const Duration(days: -3)),
      appt('absent', AppointmentStatus.noShow, const Duration(days: -5)),
    ];
    await openPast(tester);

    expect(listed(tester), ['unconf', 'absent']);
    expect(find.byType(VisitSummary), findsNothing);
    expect(find.text('dépensés'), findsNothing);
  });

  testWidgets('with nothing past, the empty state says so', (tester) async {
    current = [
      appt('next', AppointmentStatus.confirmed, const Duration(days: 2)),
    ];
    await openPast(tester);

    expect(find.text('Aucun rendez-vous passé'), findsOneWidget);
    expect(
      find.text('Vos rendez-vous passés apparaîtront ici.'),
      findsOneWidget,
    );
  });
}
