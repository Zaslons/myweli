import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/core/utils/salon_id.dart';
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
      providerId: SalonId('p1'),
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

  // ── consumer-app-truth.md §2.2 and §2.7 ───────────────────────────────────
  group('cancelling: only an open booking, and the salon\'s rule', () {
    Appointment booking(
      String id, {
      AppointmentStatus status = AppointmentStatus.confirmed,
      Duration ahead = const Duration(days: 2),
      double deposit = 5000,
      String? proof = 'https://cdn.myweli.com/deposit/p.jpg',
    }) => Appointment(
      id: id,
      userId: 'u1',
      providerId: SalonId('p1'),
      serviceIds: const ['s1'],
      appointmentDate: DateTime.now().add(ahead),
      status: status,
      totalPrice: 20000,
      depositAmount: deposit,
      depositScreenshotUrl: proof,
      createdAt: DateTime.now(),
    );

    Future<void> open(WidgetTester tester, Appointment a) async {
      when(
        () => appointments.getAppointmentById(a.id),
      ).thenAnswer((_) async => ApiResponse.success(a));
      await tester.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
            ChangeNotifierProvider(create: (_) => LocalityProvider()),
          ],
          home: AppointmentDetailScreen(appointmentId: a.id),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> askToCancel(WidgetTester tester) async {
      final button = find.text('Annuler le rendez-vous');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('a no-show offers no « Annuler », no « Reporter »', (
      tester,
    ) async {
      // The server refuses to cancel a closed booking (`invalid_state`).
      await open(
        tester,
        booking(
          'ns',
          status: AppointmentStatus.noShow,
          ahead: const Duration(days: -3),
        ),
      );
      expect(find.text('Annuler le rendez-vous'), findsNothing);
      expect(find.text('Reporter'), findsNothing);
    });

    testWidgets('no proof sent: says so, and promises nothing', (tester) async {
      await open(
        tester,
        booking('np', status: AppointmentStatus.pending, proof: null),
      );
      await askToCancel(tester);
      expect(
        find.text(
          'Vous n’avez envoyé aucun justificatif d’acompte pour ce '
          'rendez-vous.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('remboursé'), findsNothing);
    });

    testWidgets('on time, with a proof: it comes back, from the salon', (
      tester,
    ) async {
      await open(tester, booking('ok'));
      await askToCancel(tester);
      expect(
        find.textContaining('vous revient, car vous annulez plus de'),
        findsOneWidget,
      );
      expect(
        find.textContaining('MyWeli ne détient aucun acompte'),
        findsOneWidget,
      );
      expect(find.textContaining('sera remboursé.'), findsNothing);
    });

    testWidgets('late, with a proof: the salon keeps it', (tester) async {
      await open(tester, booking('late', ahead: const Duration(hours: 5)));
      await askToCancel(tester);
      expect(
        find.textContaining('ne sera pas remboursé, car vous annulez moins de'),
        findsOneWidget,
      );
    });
  });
}
