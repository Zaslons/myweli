import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/screens/appointments/appointment_detail_screen.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _MockAppointments extends Mock implements AppointmentServiceInterface {}

/// A client's own booking at a salon that STOPPED (§21 row 82, §6 cells 6–7).
///
/// **What this is really testing.** Decision C closes the public salon read, so
/// a salon that goes `draft` or `suspended` disappears from every anonymous
/// surface. The client who booked there last month is not an anonymous
/// surface: they hold the booking, the server hydrates it, and the screen has
/// to do two things it never did — SAY the salon stopped, and stop offering
/// the actions the server would refuse.
///
/// The line between hidden and kept is the point, so both halves are asserted.
/// « Reporter » goes because the server refuses the move. « Annuler » stays
/// because a stopped salon must not trap a client in a booking. « Appeler » and
/// « WhatsApp » stay because a stopped salon is exactly when a client needs to
/// reach it — and those numbers used to VANISH here, with the app blaming the
/// phone number (« Numéro indisponible. ») for something that was never about
/// the number.
void main() {
  final appointments = _MockAppointments();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    serviceLocator.appointmentService = appointments;
    serviceLocator.localityService = MockLocalityService();
  });

  Appointment appt({String? providerStatus}) => Appointment(
    id: 'a1',
    userId: 'u1',
    providerId: 'p1',
    serviceIds: const ['s1'],
    appointmentDate: DateTime.now().add(const Duration(days: 2)),
    status: AppointmentStatus.confirmed,
    totalPrice: 10000,
    createdAt: DateTime.now(),
    providerName: 'Beauté Divine',
    providerStatus: providerStatus,
    providerPhone: '+2250711223344',
    providerWhatsapp: '+2250711223355',
    providerCountryCode: 'CI',
  );

  Widget host() => wrapApp(
    providers: [
      ChangeNotifierProvider(create: (_) => AppointmentProvider()),
      ChangeNotifierProvider(create: (_) => LocalityProvider()),
    ],
    home: const AppointmentDetailScreen(appointmentId: 'a1'),
  );

  Future<void> pump(WidgetTester tester, Appointment a) async {
    when(
      () => appointments.getAppointmentById('a1'),
    ).thenAnswer((_) async => ApiResponse.success(a));
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();
  }

  group('a suspended salon', () {
    testWidgets('says so, in the tense that means « was stopped »', (
      tester,
    ) async {
      await pump(tester, appt(providerStatus: 'suspended'));
      expect(
        find.text('Ce salon ne prend plus de rendez-vous sur MyWeli.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('withholds « Reporter », keeps the way out and the phone', (
      tester,
    ) async {
      await pump(tester, appt(providerStatus: 'suspended'));
      expect(find.text('Reporter'), findsNothing);
      expect(find.text('Annuler le rendez-vous'), findsOneWidget);
      expect(find.text('Appeler'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('a draft salon', () {
    testWidgets('gets the OTHER tense — « has never published »', (
      tester,
    ) async {
      // The pair for the sentence: one message for both states would pass the
      // suspended test and be wrong here, which is exactly the conflation row
      // 82 exists to end.
      await pump(tester, appt(providerStatus: 'draft'));
      expect(
        find.text('Ce salon n’accepte pas encore de réservations en ligne.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('a live salon', () {
    testWidgets('says nothing and offers everything', (tester) async {
      // The pair for the gating. Without it, a screen that hid « Reporter »
      // unconditionally — or one that showed the sentence always — would pass
      // every assertion above.
      await pump(tester, appt(providerStatus: 'active'));
      expect(find.text('Reporter'), findsOneWidget);
      expect(
        find.text('Ce salon ne prend plus de rendez-vous sur MyWeli.'),
        findsNothing,
      );
      expect(
        find.text('Ce salon n’accepte pas encore de réservations en ligne.'),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('and so does a salon with NO status at all', (tester) async {
      // The NULL trap, on a screen. Seeded salons carry no stored status and
      // Postgres reads NULL as active; a pre-enrichment payload has no field.
      // Spelling the check `providerStatus == 'active'` would hide « Reporter »
      // on every one of them.
      await pump(tester, appt());
      expect(find.text('Reporter'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
