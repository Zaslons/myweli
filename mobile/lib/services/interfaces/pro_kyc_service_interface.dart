import '../../models/api_response.dart';
import '../../models/kyc_document.dart';

abstract class ProKycServiceInterface {
  /// The provider's current KYC state (status + submitted documents).
  Future<ApiResponse<KycStatus>> getKycStatus(String providerUserId);

  /// Submit documents for review. Moves the provider to `pending`.
  Future<ApiResponse<KycStatus>> submitKyc({
    required String providerUserId,
    required List<KycDocument> documents,
  });
}
