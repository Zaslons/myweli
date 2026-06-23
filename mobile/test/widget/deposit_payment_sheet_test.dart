import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/widgets/booking/deposit_payment_sheet.dart';

void main() {
  Widget host({required MobileMoneyOperator operator}) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDepositPaymentSheet(
                context,
                depositAmount: 6000,
                balanceDue: 14000,
                providerId: 'p1',
                providerName: 'Beauté Divine',
                serviceIds: const ['s1'],
                appointmentDateTime: DateTime(2024, 6, 24, 10),
                depositOperator: operator,
                depositNumber: '+2250707123456',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('Wave handle shows the Wave button + copyable number',
      (tester) async {
    await tester.pumpWidget(host(operator: MobileMoneyOperator.wave));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text("Payer l'acompte"), findsOneWidget);
    expect(find.text('Payer avec Wave'), findsOneWidget);
    expect(find.text('+2250707123456'), findsOneWidget);
    expect(find.text('Copier'), findsOneWidget);
    expect(find.text("J'ai payé l'acompte"), findsOneWidget);
  });

  testWidgets('a non-Wave operator shows copy only (no Wave button)',
      (tester) async {
    await tester.pumpWidget(host(operator: MobileMoneyOperator.orangeMoney));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Payer avec Wave'), findsNothing);
    expect(find.text('Copier'), findsOneWidget);
  });
}
