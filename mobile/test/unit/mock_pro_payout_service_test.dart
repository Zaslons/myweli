import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/payout.dart';
import 'package:myweli/services/mock/mock_pro_payout_service.dart';

void main() {
  late MockProPayoutService service;

  setUp(() => service = MockProPayoutService());

  test('getPayoutAccount returns a seeded balance + history', () async {
    final res = await service.getPayoutAccount('provider1');

    expect(res.success, isTrue);
    expect(res.data!.availableBalance, greaterThan(0));
    expect(res.data!.payouts, isNotEmpty);
  });

  test('requestPayout moves money from available into a pending payout',
      () async {
    final before = (await service.getPayoutAccount('provider1')).data!;
    final amount = before.availableBalance / 2;

    final req = await service.requestPayout(
      providerId: 'provider1',
      amount: amount,
      operator: MobileMoneyOperator.wave,
    );
    expect(req.success, isTrue);
    expect(req.data!.status, PayoutStatus.pending);

    final after = (await service.getPayoutAccount('provider1')).data!;
    expect(after.availableBalance,
        closeTo(before.availableBalance - amount, 0.01));
    expect(after.pendingBalance, closeTo(amount, 0.01));
  });

  test('requestPayout rejects an amount above the balance', () async {
    final account = (await service.getPayoutAccount('provider1')).data!;

    final res = await service.requestPayout(
      providerId: 'provider1',
      amount: account.availableBalance + 1,
      operator: MobileMoneyOperator.wave,
    );

    expect(res.success, isFalse);
    expect(res.error, 'Solde insuffisant');
  });
}
