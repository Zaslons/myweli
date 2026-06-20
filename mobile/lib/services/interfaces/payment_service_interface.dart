import '../../models/api_response.dart';
import '../../models/payment.dart';

abstract class PaymentServiceInterface {
  /// Charges a booking deposit to the chosen Mobile Money operator.
  Future<ApiResponse<PaymentResult>> payDeposit({
    required double amount,
    required MobileMoneyOperator operator,
    String? reference,
  });
}
