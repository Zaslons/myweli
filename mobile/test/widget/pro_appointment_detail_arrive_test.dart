import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/screens/provider/appointments/pro_appointment_detail_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// Parity 1.10 (J1b §4.2 debt): « Client arrivé » on the pro DETAIL page —
/// same-day confirmed only, hidden once arrivedAt is set.
void main() {
  final service = _MockProService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = service;
  });

  setUp(() => reset(service));

  Appointment appt({DateTime? date, DateTime? arrivedAt}) => Appointment(
        id: 'a1',
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        // Same-day-safe: a fixed +2h crossed midnight on late-UTC CI runs
        // (a 22h-24h flake window) — "now" is inside today by definition.
        appointmentDate: date ?? DateTime.now(),
        status: AppointmentStatus.confirmed,
        totalPrice: 10000,
        clientName: 'Koffi',
        arrivedAt: arrivedAt,
        createdAt: DateTime.now(),
      );

  Future<Widget> host(Appointment a) async {
    when(() => service.getProviderAppointments(any(),
            status: any(named: 'status')))
        .thenAnswer((_) async => ApiResponse.success([a]));
    // Pre-load: the screen reads the provider's list (auth-gated reload only).
    final appointments = ProAppointmentProvider();
    await appointments.loadAppointments('p1');
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ChangeNotifierProvider.value(value: appointments),
        ChangeNotifierProvider(create: (_) => ProJournalProvider()),
      ],
      child: const MaterialApp(
        home: ProAppointmentDetailScreen(appointmentId: 'a1'),
      ),
    );
  }

  testWidgets('same-day confirmed → « Client arrivé » marks the arrival',
      (tester) async {
    when(() => service.markArrived('a1'))
        .thenAnswer((_) async => ApiResponse.success(true));

    await tester.pumpWidget(await host(appt()));
    await tester.pump();

    final button = find.text('Client arrivé');
    expect(button, findsOneWidget);
    await tester.scrollUntilVisible(button, 200);
    await tester.tap(button);
    await tester.pump();

    verify(() => service.markArrived('a1')).called(1);
    expect(find.text('Arrivée enregistrée'), findsOneWidget);
    // Drain the session-restore / snackbar timers before teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('hidden on another day and once arrived', (tester) async {
    await tester.pumpWidget(
      await host(appt(date: DateTime.now().add(const Duration(days: 2)))),
    );
    await tester.pump();
    expect(find.text('Client arrivé'), findsNothing);

    await tester.pumpWidget(
      await host(appt(arrivedAt: DateTime.now())),
    );
    await tester.pump();
    expect(find.text('Client arrivé'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
