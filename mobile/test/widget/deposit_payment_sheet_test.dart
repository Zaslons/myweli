import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/booking/deposit_payment_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDepositPaymentSheet(
                context,
                depositAmount: 6000,
                balanceDue: 14000,
                providerId: 'p1',
                serviceIds: const ['s1'],
                appointmentDateTime: DateTime(2024, 6, 24, 10),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('renders the amount, operators and pay button', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text("Payer l'acompte"), findsOneWidget);
    expect(find.text('Wave'), findsOneWidget);
    expect(find.text('Orange Money'), findsOneWidget);
    expect(find.text('MTN MoMo'), findsOneWidget);
    expect(find.text('Moov Money'), findsOneWidget);
    expect(find.textContaining('via Wave'), findsOneWidget);
  });

  testWidgets('selecting an operator updates the pay button', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Orange Money'));
    await tester.pump();

    expect(find.textContaining('via Orange Money'), findsOneWidget);
  });
}
