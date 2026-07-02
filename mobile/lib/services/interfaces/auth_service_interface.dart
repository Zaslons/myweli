import '../../models/api_response.dart';
import '../../models/provider_user.dart';
import '../../models/user.dart';

abstract class AuthServiceInterface {
  // Phone OTP — dormant at launch (AUTH_METHODS gates the backend routes);
  // kept for the Termii-era phone VERIFICATION reuse.
  Future<ApiResponse<String>> sendOtp(String phoneNumber);
  Future<ApiResponse<User>> verifyOtp(String phoneNumber, String otp);

  // Auth overhaul (docs/design/app-auth-social.md): Google + Apple + email OTP.
  Future<ApiResponse<User>> signInWithGoogle();
  Future<ApiResponse<User>> signInWithApple();
  Future<ApiResponse<String>> requestEmailOtp(String email);
  Future<ApiResponse<User>> verifyEmailOtp(String email, String code);

  Future<void> logout();
  Future<User?> getCurrentUser();

  /// [phone] sets the CONTACT phone (unverified until proven via SMS later);
  /// empty string clears it.
  Future<ApiResponse<User>> updateUser(
      {String? name, String? email, String? avatarUrl, String? phone});

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
