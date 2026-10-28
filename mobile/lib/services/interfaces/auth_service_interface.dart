import '../../core/utils/salon_id.dart';
import '../../models/api_response.dart';
import '../../models/pro_membership.dart';
import '../../models/provider_login_result.dart';
import '../../models/provider_user.dart';
import '../../models/salon_facts.dart';
import '../../models/salon_market.dart';
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

  /// The client session ended WITHOUT a sign-out: the server refused to renew
  /// it (a refresh token revoked, expired or reused, an account deleted
  /// elsewhere). `AuthProvider` ends the account on it — the stored session
  /// is already gone. Never fired by [logout] or [deleteAccount], nor for the
  /// provider session. docs/design/consumer-account-scope.md §2.4.
  Stream<void> get sessionEnded;

  /// [phone] sets the CONTACT phone (unverified until proven via SMS later);
  /// empty string clears it.
  Future<ApiResponse<User>> updateUser({
    String? name,
    String? email,
    String? avatarUrl,
    String? phone,
  });

  /// Permanently delete the signed-in user's account. Irreversible.
  Future<ApiResponse<void>> deleteAccount();

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
    String invitationId,
    InvitationProof proof,
  );
  Future<ApiResponse<bool>> declineProviderInvitation(
    String invitationId,
    InvitationProof proof,
  );

  Future<ProviderUser?> getCurrentProvider();
  Future<void> logoutProvider();

  /// The PROVIDER session ended without a sign-out — [sessionEnded]'s twin
  /// for the Pro app (a refused `/auth/provider/refresh`). `ProAuthProvider`
  /// ends the account on it. docs/design/pro-account-scope.md §2.3.
  Stream<void> get providerSessionEnded;

  /// Team access R4b: cache the last-fetched membership INSIDE the persisted
  /// provider session (instant cold-start shaping; refreshed from
  /// GET /me/provider each start). No-op when signed out.
  Future<void> cacheProviderMembership(ProMembership? membership);
  Future<ProMembership?> getCachedProviderMembership();

  /// The acting salon's market facts (timezone, currency, country, area),
  /// cached INSIDE the persisted provider session next to the membership —
  /// a cold start whose GET /me/provider fails still knows the salon's clock
  /// (docs/design/pro-app-salon-not-loaded.md §3.1). `null` CLEARS them.
  /// No-op when signed out.
  Future<void> cacheProviderSalonMarket(SalonMarket? market);
  Future<SalonMarket?> getCachedProviderSalonMarket();

  /// What « Profil » shows of the acting salon (name, category, address,
  /// phone), cached INSIDE the persisted provider session like the market —
  /// an offline cold start still shows them (product-questions-batch8.md
  /// §2.3, B8.3). `null` CLEARS them. No-op when signed out.
  Future<void> cacheProviderSalonFacts(SalonFacts? facts);
  Future<SalonFacts?> getCachedProviderSalonFacts();

  /// R6 multi-salons: persist/restore the switched-to salon INSIDE the
  /// provider session (cold-start continuity; `null` = the default salon).
  /// The API layer reads it to scope the session-resolved endpoints; the
  /// server revalidates the membership on every request (T55).
  Future<void> setSelectedProviderSalon(SalonId? salonId);
  Future<SalonId?> getSelectedProviderSalon();
}
