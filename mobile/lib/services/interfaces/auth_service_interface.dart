import '../../models/api_response.dart';
import '../../models/provider_user.dart';
import '../../models/user.dart';

abstract class AuthServiceInterface {
  Future<ApiResponse<String>> sendOtp(String phoneNumber);
  Future<ApiResponse<User>> verifyOtp(String phoneNumber, String otp);
  Future<void> logout();
  Future<User?> getCurrentUser();
  Future<ApiResponse<User>> updateUser(
      {String? name, String? email, String? avatarUrl});

  /// Permanently delete the signed-in user's account. Irreversible.
  Future<ApiResponse<void>> deleteAccount();

  // Provider methods
  Future<ApiResponse<String>> sendOtpToProvider(String phoneNumber);
  Future<ApiResponse<ProviderUser>> verifyOtpForProvider(
      String phoneNumber, String otp);
  Future<ApiResponse<ProviderUser>> registerProvider({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  });
  Future<ProviderUser?> getCurrentProvider();
  Future<void> logoutProvider();
}
