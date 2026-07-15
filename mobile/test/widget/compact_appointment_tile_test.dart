import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/widgets/booking/compact_appointment_tile.dart';

import '../support/pump_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  Widget wrap(Widget child) => wrapApp(home: Scaffold(body: child));

  Appointment appointment() => Appointment(
        id: 'a1',
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: DateTime(2025, 5, 12, 10),
        status: AppointmentStatus.completed,
        totalPrice: 20000,
        createdAt: DateTime(2025),
      );

  testWidgets('shows the hint when provided', (tester) async {
    await tester.pumpWidget(
      wrap(CompactAppointmentTile(
        appointment: appointment(),
        providerName: 'Salon Excellence',
        onTap: () {},
        hint: 'Réserver à nouveau',
      )),
    );

    expect(find.text('Réserver à nouveau'), findsOneWidget);
  });

  testWidgets('shows no hint when none is provided', (tester) async {
    await tester.pumpWidget(
      wrap(CompactAppointmentTile(
        appointment: appointment(),
        providerName: 'Salon Excellence',
        onTap: () {},
      )),
    );

    expect(find.text('Réserver à nouveau'), findsNothing);
  });
}
