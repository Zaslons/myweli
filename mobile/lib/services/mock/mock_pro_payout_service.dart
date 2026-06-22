import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/payment.dart';
import '../../models/payout.dart';
import '../interfaces/pro_payout_service_interface.dart';
import 'mock_data.dart';

class _PayoutState {
  double available;
  final List<Payout> payouts;
  _PayoutState(this.available, this.payouts);
}

class MockProPayoutService implements ProPayoutServiceInterface {
  final Map<String, _PayoutState> _byProvider = {};

  _PayoutState _stateFor(String providerId) {
    return _byProvider.putIfAbsent(providerId, () {
      // Seed the available balance from deposits collected on this provider's
      // honoured (non-cancelled, non-no-show) appointments. Mock appointments
      // don't carry real deposit amounts (the backend will), so fall back to a
      // nominal collected deposit per honoured booking.
      const nominalDeposit = 3000.0;
      final collected = MockData.appointments
          .where((a) =>
              a.providerId == providerId &&
              a.status != AppointmentStatus.cancelled &&
              a.status != AppointmentStatus.noShow)
          .fold<double>(
            0,
            (sum, a) =>
                sum + (a.depositAmount > 0 ? a.depositAmount : nominalDeposit),
          );
      final seeded = <Payout>[
        Payout(
          id: 'po_seed_1',
          amount: 24000,
          status: PayoutStatus.paid,
          requestedAt: DateTime.now().subtract(const Duration(days: 12)),
          operator: MobileMoneyOperator.wave,
          reference: 'WV-1024',
        ),
      ];
      return _PayoutState(collected, seeded);
    });
  }

  double _pending(List<Payout> payouts) => payouts
      .where((p) => p.status == PayoutStatus.pending)
      .fold<double>(0, (sum, p) => sum + p.amount);

  @override
  Future<ApiResponse<PayoutAccount>> getPayoutAccount(String providerId) async {
    await Future.delayed(AppConstants.mockDelay);
    final state = _stateFor(providerId);
    final sorted = [...state.payouts]
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return ApiResponse.success(PayoutAccount(
      availableBalance: state.available,
      pendingBalance: _pending(state.payouts),
      payouts: sorted,
    ));
  }

  @override
  Future<ApiResponse<Payout>> requestPayout({
    required String providerId,
    required double amount,
    required MobileMoneyOperator operator,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final state = _stateFor(providerId);
    if (amount <= 0) {
      return ApiResponse.error('Montant invalide');
    }
    if (amount > state.available) {
      return ApiResponse.error('Solde insuffisant');
    }
    final payout = Payout(
      id: 'po_${DateTime.now().millisecondsSinceEpoch}',
      amount: amount,
      status: PayoutStatus.pending,
      requestedAt: DateTime.now(),
      operator: operator,
    );
    state.available -= amount;
    state.payouts.add(payout);
    return ApiResponse.success(payout, message: 'Virement demandé');
  }
}
