import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ProviderProvider(),
          child: Scaffold(body: child),
        ),
      );

  Appointment appt({String? clientName}) => Appointment(
        id: 'a1',
        userId: clientName == null ? 'u1' : 'manual',
        providerId: 'p1',
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
      wrap(AppointmentCard(appointment: appt(clientName: 'Awa'), onTap: () {})),
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
}
