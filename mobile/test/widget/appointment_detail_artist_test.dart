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
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _MockAppointments extends Mock implements AppointmentServiceInterface {}

/// A provider service that fails the test if anything touches it.
///
/// This is `salon_preview_test.dart`'s idiom, and it is here for the same
/// reason: the property under test is **which door the screen knocks on**, and
/// the only way to assert a door was not used is to make using it fatal.
class _ForbiddenProviderService implements ProviderServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => fail(
    'the consumer appointment detail called '
    '`providerService.${invocation.memberName}` — every salon fact it needs '
    'rides the appointment now (Decision C). A public `GET /providers/{id}` '
    'from this screen is the defect this test exists to prevent: the route '
    'stops serving a salon that is draft or suspended, and a client looking '
    'at their OWN booking would silently lose the salon name, the phone '
    'number and the Mobile Money handle they owe a deposit to.',
  );
}

/// Parity 1.8 (app half): the consumer detail shows the chosen spécialiste —
/// **and now, that it does so without asking the anonymous door.**
///
/// **This file used to bless the bug.** Its second test stubbed
/// `getProviderById` to fail and asserted the « Spécialiste » row simply
/// vanished — *« facts stay null → OK »*. That was true of the code and false
/// of the product: the same failed fetch also emptied the deposit block, made
/// « Appeler » snackbar « Numéro indisponible. » (blaming the phone number for
/// a salon-state problem), and wrote a calendar entry titled « Rendez-vous —
/// le salon » with zero duration while reporting success. A test that pins a
/// silent degradation as acceptable is how six of them survived.
///
/// The rewrite is not a weakening: the stub is gone because the CALL is gone.
/// `_ForbiddenProviderService` is strictly stronger than the old mock — it
/// cannot be satisfied by any implementation that still fetches.
void main() {
  final appointments = _MockAppointments();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    serviceLocator.appointmentService = appointments;
    serviceLocator.providerService = _ForbiddenProviderService();
    // MP2: the detail loads the locality tree for the hint's country label.
    serviceLocator.localityService = MockLocalityService();
  });

  Appointment appt({String? artistId, String? artistName}) => Appointment(
    id: 'a1',
    userId: 'u1',
    providerId: 'p1',
    serviceIds: const ['s1'],
    appointmentDate: DateTime.now().add(const Duration(days: 2)),
    status: AppointmentStatus.confirmed,
    totalPrice: 10000,
    artistId: artistId,
    createdAt: DateTime.now(),
    // The enrichment the server performs (`withProviderFacts`).
    providerName: 'Beauté Divine',
    providerStatus: 'active',
    providerPhone: '+22500',
    providerCountryCode: 'CI',
    artistName: artistName,
  );

  Widget host() => wrapApp(
    providers: [
      ChangeNotifierProvider(create: (_) => AppointmentProvider()),
      ChangeNotifierProvider(create: (_) => LocalityProvider()),
    ],
    home: const AppointmentDetailScreen(appointmentId: 'a1'),
  );

  testWidgets('shows « Spécialiste » resolved from the salon team', (
    tester,
  ) async {
    when(() => appointments.getAppointmentById('a1')).thenAnswer(
      (_) async =>
          ApiResponse.success(appt(artistId: 'ar1', artistName: 'Awa Diabaté')),
    );

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    expect(find.text('Spécialiste'), findsOneWidget);
    expect(find.text('Awa Diabaté'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no artist on the booking → no row', (tester) async {
    // The pair: without it, a screen that rendered the row unconditionally
    // would pass the test above.
    when(
      () => appointments.getAppointmentById('a1'),
    ).thenAnswer((_) async => ApiResponse.success(appt()));

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    expect(find.text('Spécialiste'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
