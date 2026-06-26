import '../../models/api_response.dart';
import '../../models/kyc_document.dart';

abstract class ProKycServiceInterface {
  /// The provider's current KYC state (status + submitted documents).
  Future<ApiResponse<KycStatus>> getKycStatus(String providerUserId);

  /// Upload a KYC document (image or PDF at [source]) to **private** storage;
  /// returns the storage key to attach to a [KycDocument] before submitting.
  Future<ApiResponse<String>> uploadDocument({
    required String source,
    required String contentType,
  });

  /// Submit documents for review. Moves the provider to `pending`.
  Future<ApiResponse<KycStatus>> submitKyc({
    required String providerUserId,
    required List<KycDocument> documents,
  });
}
