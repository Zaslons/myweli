import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/payment.dart';
import '../interfaces/payment_service_interface.dart';

/// Mock Mobile Money payment. Always succeeds after a short delay — the real
/// Wave / Orange Money / MTN / Moov integration is Phase 4 (via an aggregator).
class MockPaymentService implements PaymentServiceInterface {
  @override
  Future<ApiResponse<PaymentResult>> payDeposit({
    required double amount,
    required MobileMoneyOperator operator,
    String? reference,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success(
      PaymentResult(
        success: true,
        reference: reference ?? 'MOCK-${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
  }
}
