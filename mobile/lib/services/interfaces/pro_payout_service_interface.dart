import '../../models/api_response.dart';
import '../../models/payment.dart';
import '../../models/payout.dart';

abstract class ProPayoutServiceInterface {
  /// The provider's available/pending balance + payout history.
  Future<ApiResponse<PayoutAccount>> getPayoutAccount(String providerId);

  /// Request a payout of [amount] to the given Mobile Money operator. Creates
  /// a pending payout; the actual settlement is performed server-side.
  Future<ApiResponse<Payout>> requestPayout({
    required String providerId,
    required double amount,
    required MobileMoneyOperator operator,
  });
}
