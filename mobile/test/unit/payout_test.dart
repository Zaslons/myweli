import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/payout.dart';

void main() {
  test('Payout survives a JSON round-trip', () {
    final payout = Payout(
      id: 'po_1',
      amount: 18000,
      status: PayoutStatus.paid,
      requestedAt: DateTime(2026, 6, 12, 9, 30),
      operator: MobileMoneyOperator.orangeMoney,
      reference: 'OM-77',
    );

    final restored = Payout.fromJson(payout.toJson());

    expect(restored, payout);
    expect(restored.status, PayoutStatus.paid);
    expect(restored.operator, MobileMoneyOperator.orangeMoney);
    expect(restored.reference, 'OM-77');
  });

  test('Payout tolerates a missing reference', () {
    final payout = Payout(
      id: 'po_2',
      amount: 5000,
      status: PayoutStatus.pending,
      requestedAt: DateTime(2026, 6, 20),
      operator: MobileMoneyOperator.wave,
    );

    final restored = Payout.fromJson(payout.toJson());

    expect(restored.reference, isNull);
    expect(restored.status, PayoutStatus.pending);
  });
}
