import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/screens/appointments/appointment_detail_screen.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _Appointments extends Mock implements AppointmentServiceInterface {}

/// docs/design/hygiene-batch9.md §14 (B9.8) — `AppointmentProvider`'s
/// selection is app-wide and outlives the detail screen. On the way from
/// booking A to booking B it still held A, and the screen showed A's details
/// — and A's « Envoyer l’acompte » and « Reporter », which act on the shown
/// booking's id, while « Annuler » acted on B's — until B answered.
void main() {
  final appointments = _Appointments();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    serviceLocator.appointmentService = appointments;
    serviceLocator.localityService = MockLocalityService();
  });

  testWidgets('a booking\'s screen never shows another booking — not even on '
      'its first frame', (tester) async {
    // The price tells them apart: the screen shows it, not the salon's name
    // — in the formatter's own spacing.
    String priceOf(double p) => Formatters.formatCurrency(p);
    Appointment booking(String id, double price) => Appointment(
      id: id,
      userId: 'u1',
      providerId: 'p1',
      serviceIds: const ['s1'],
      appointmentDate: DateTime.now().add(const Duration(days: 2)),
      status: AppointmentStatus.confirmed,
      totalPrice: price,
      createdAt: DateTime.now(),
    );
    when(
      () => appointments.getAppointmentById('a'),
    ).thenAnswer((_) async => ApiResponse.success(booking('a', 10000)));
    when(
      () => appointments.getAppointmentById('b'),
    ).thenAnswer((_) async => ApiResponse.success(booking('b', 25000)));

    final shared = AppointmentProvider();
    await shared.loadAppointmentById('a');

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<AppointmentProvider>.value(value: shared),
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        home: const AppointmentDetailScreen(appointmentId: 'b'),
      ),
    );
    // The first frame: the post-frame read of B has not started, and the
    // app-wide selection is still A.
    expect(find.text(priceOf(10000)), findsNothing);
    expect(find.bySemanticsLabel('Chargement…'), findsOneWidget);

    await tester.pump();
    await tester.pump();
    expect(find.text(priceOf(25000)), findsOneWidget);
    expect(find.text(priceOf(10000)), findsNothing);
    // The country label's locality read (mock latency).
    await tester.pump(const Duration(milliseconds: 400));
  });
}
