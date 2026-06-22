import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/payout.dart';
import 'package:myweli/providers/pro_payout_provider.dart';
import 'package:myweli/services/interfaces/pro_payout_service_interface.dart';

class _MockPayoutService extends Mock implements ProPayoutServiceInterface {}

void main() {
  late _MockPayoutService service;

  setUpAll(() {
    registerFallbackValue(MobileMoneyOperator.wave);
    service = _MockPayoutService();
    serviceLocator.proPayoutService = service;
  });

  setUp(() => reset(service));

  Payout seedPayout() => Payout(
        id: 'po_seed',
        amount: 24000,
        status: PayoutStatus.paid,
        requestedAt: DateTime(2026, 6, 1),
        operator: MobileMoneyOperator.wave,
      );

  test('load populates balance, pending and history', () async {
    when(() => service.getPayoutAccount(any())).thenAnswer(
      (_) async => ApiResponse.success(PayoutAccount(
        availableBalance: 18000,
        pendingBalance: 6000,
        payouts: [seedPayout()],
      )),
    );

    final provider = ProPayoutProvider();
    await provider.load('provider1');

    expect(provider.availableBalance, 18000);
    expect(provider.pendingBalance, 6000);
    expect(provider.payouts, hasLength(1));
    expect(provider.isLoading, isFalse);
    expect(provider.loadFailed, isFalse);
    expect(provider.canRequest, isTrue);
  });

  test('a failed load flips loadFailed and surfaces the error', () async {
    when(() => service.getPayoutAccount(any()))
        .thenAnswer((_) async => ApiResponse.error('boom'));

    final provider = ProPayoutProvider();
    await provider.load('provider1');

    expect(provider.loadFailed, isTrue);
    expect(provider.error, 'boom');
    expect(provider.canRequest, isFalse);
  });

  test('requestPayout success reloads the account and returns true', () async {
    when(() => service.requestPayout(
          providerId: any(named: 'providerId'),
          amount: any(named: 'amount'),
          operator: any(named: 'operator'),
        )).thenAnswer((_) async => ApiResponse.success(Payout(
          id: 'po_new',
          amount: 6000,
          status: PayoutStatus.pending,
          requestedAt: DateTime(2026, 6, 22),
          operator: MobileMoneyOperator.wave,
        )));
    when(() => service.getPayoutAccount(any())).thenAnswer(
      (_) async => ApiResponse.success(const PayoutAccount(
        availableBalance: 12000,
        pendingBalance: 6000,
      )),
    );

    final provider = ProPayoutProvider();
    final ok = await provider.requestPayout(
      providerId: 'provider1',
      amount: 6000,
      operator: MobileMoneyOperator.wave,
    );

    expect(ok, isTrue);
    expect(provider.availableBalance, 12000); // from the reload
    verify(() => service.requestPayout(
          providerId: 'provider1',
          amount: 6000,
          operator: MobileMoneyOperator.wave,
        )).called(1);
  });

  test('requestPayout failure returns false and sets the error', () async {
    when(() => service.requestPayout(
          providerId: any(named: 'providerId'),
          amount: any(named: 'amount'),
          operator: any(named: 'operator'),
        )).thenAnswer((_) async => ApiResponse.error('Solde insuffisant'));

    final provider = ProPayoutProvider();
    final ok = await provider.requestPayout(
      providerId: 'provider1',
      amount: 999999,
      operator: MobileMoneyOperator.wave,
    );

    expect(ok, isFalse);
    expect(provider.error, 'Solde insuffisant');
    verifyNever(() => service.getPayoutAccount(any()));
  });
}
