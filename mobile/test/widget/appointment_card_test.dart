import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:provider/provider.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';

void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

  Widget wrap(Widget child) => wrapApp(
    providers: [ChangeNotifierProvider(create: (_) => ProviderProvider())],
    home: Scaffold(body: child),
  );

  Appointment appt({String? clientName}) => Appointment(
    id: 'a1',
    userId: clientName == null ? 'u1' : 'manual',
    providerId: SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: DateTime(2026, 6, 30, 10),
    status: AppointmentStatus.confirmed,
    totalPrice: 20000,
    createdAt: DateTime(2026),
    clientName: clientName,
  );

  testWidgets('shows the salon-entered badge when clientName is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppointmentCard(
          appointment: appt(clientName: 'Awa'),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Réservé par votre salon'), findsOneWidget);
  });

  testWidgets('hides the badge for a normal booking', (tester) async {
    await tester.pumpWidget(
      wrap(AppointmentCard(appointment: appt(), onTap: () {})),
    );
    await tester.pump();
    expect(find.text('Réservé par votre salon'), findsNothing);
  });

  // consumer-app-truth.md §2.6: the booking carries its salon's name and its
  // services' names. The discovery list here is EMPTY (nothing loaded), which
  // is the case of a salon in another commune, on page two, or gone from the
  // listing — it used to read « Salon » with no services.
  testWidgets('reads the salon and the services from the booking itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppointmentCard(
          appointment: appt().copyWith(
            providerName: 'Beauté Awa',
            serviceNames: const ['Tresses', 'Pose de vernis'],
          ),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Beauté Awa'), findsOneWidget);
    expect(find.text('Salon'), findsNothing);
    expect(find.text('Tresses'), findsOneWidget);
    expect(find.text('Pose de vernis'), findsOneWidget);
  });

  testWidgets('with no name anywhere, says « Salon » (§17.2)', (tester) async {
    await tester.pumpWidget(
      wrap(AppointmentCard(appointment: appt(), onTap: () {})),
    );
    await tester.pump();
    expect(find.text('Salon'), findsOneWidget);
  });

  // §2.7: a past booking the salon never confirmed is not « Terminé ».
  testWidgets('a past pending booking reads « Non confirmé »', (tester) async {
    freezeClock(DateTime(2026, 7, 2, 12));
    await tester.pumpWidget(
      wrap(
        AppointmentCard(
          appointment: appt().copyWith(status: AppointmentStatus.pending),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Non confirmé'), findsOneWidget);
    expect(find.text('En attente'), findsNothing);
    expect(find.text('Terminé'), findsNothing);
  });
}
