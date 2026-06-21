import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/kyc_document.dart';
import '../../models/provider_user.dart';
import '../interfaces/pro_kyc_service_interface.dart';

class MockProKycService implements ProKycServiceInterface {
  final Map<String, KycStatus> _byUser = {};

  @override
  Future<ApiResponse<KycStatus>> getKycStatus(String providerUserId) async {
    await Future.delayed(AppConstants.mockDelay);
    final status = _byUser[providerUserId] ??
        const KycStatus(status: VerificationStatus.pending);
    return ApiResponse.success(status);
  }

  @override
  Future<ApiResponse<KycStatus>> submitKyc({
    required String providerUserId,
    required List<KycDocument> documents,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    if (documents.isEmpty) {
      return ApiResponse.error('Aucun document à soumettre');
    }

    // Submission moves the provider to "pending"; an admin verifies later.
    final status = KycStatus(
      status: VerificationStatus.pending,
      documents: List.unmodifiable(documents),
    );
    _byUser[providerUserId] = status;

    return ApiResponse.success(
      status,
      message: 'Documents soumis pour vérification',
    );
  }
}
