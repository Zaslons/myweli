import '../../models/api_response.dart';
import '../../models/provider_login_result.dart';
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

  // Provider methods — phone OTP dormant at launch (AUTH_METHODS-gated).
  Future<ApiResponse<String>> sendOtpToProvider(String phoneNumber);
  Future<ApiResponse<ProviderUser>> verifyOtpForProvider(
      String phoneNumber, String otp);

  // Pro auth overhaul (docs/design/pro-auth-social.md) — LOGIN-ONLY (a salon
  // is never auto-created; `provider_not_found` → offer registration).
  // Team access R3: a verified identity with PENDING invitations comes back
  // as [ProviderLoginResult.invited] (the 202 bridge) instead of the 404;
  // Apple has no bridge in the contract (never `.invited`).
  Future<ProviderLoginResult> signInProviderWithGoogle();
  Future<ProviderLoginResult> signInProviderWithApple();
  Future<ApiResponse<String>> requestProviderEmailOtp(String email);
  Future<ProviderLoginResult> verifyProviderEmailOtp(String email, String code);

  /// Accept/decline a team invitation from the LOGIN flow (unauthenticated,
  /// identity-proven — team access R2b). Accept signs the invitee in
  /// (200 existing / 201 new bare member account) and persists the session
  /// exactly like a login.
  Future<ApiResponse<ProviderUser>> acceptProviderInvitation(
      String invitationId, InvitationProof proof);
  Future<ApiResponse<bool>> declineProviderInvitation(
      String invitationId, InvitationProof proof);

  /// Registration = identity + business fields in ONE submit (signs in too).
  /// The REQUIRED [phoneNumber] is the salon contact.
  Future<ApiResponse<ProviderUser>> registerProviderWithGoogle({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  });
  Future<ApiResponse<ProviderUser>> registerProviderWithEmail({
    required String email,
    required String code,
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  });

  Future<ProviderUser?> getCurrentProvider();
  Future<void> logoutProvider();
}
