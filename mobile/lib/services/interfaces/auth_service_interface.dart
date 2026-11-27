import '../../core/utils/salon_id.dart';
import '../../models/api_response.dart';
import '../../models/email_change_request.dart';
import '../../models/pro_membership.dart';
import '../../models/pro_sign_up_fields.dart';
import '../../models/provider_login_result.dart';
import '../../models/provider_sign_up_result.dart';
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
  ///
  /// **No `email`:** an address changes only by a code, through
  /// [requestEmailChange] and [confirmEmailChange] (B16.3, decision 261).
  /// `PATCH /me` answers `409 email_change_requires_code` to any other address
  /// than the stored one, so a parameter here could only ever carry that 409.
  Future<ApiResponse<User>> updateUser({
    String? name,
    String? avatarUrl,
    String? phone,
  });

  /// Sends a code to [email], and one to the current address when that
  /// proven address is the account's only way in (decision 265;
  /// [EmailChangeRequest.currentCodeSent]). The same answer whether or not
  /// [email] belongs to another account: « taken » is said only by
  /// [confirmEmailChange], to whoever proves the inbox (decision 262).
  /// docs/design/account-email-change.md §3.1, §5.4.
  ///
  /// Refusals: `invalid_email`, `email_unchanged` (already the account's
  /// proven address), `otp_resend_limit`, `rate_limited`,
  /// `account_suspended`, `auth_method_disabled`.
  Future<ApiResponse<EmailChangeRequest>> requestEmailChange(String email);

  /// Proves [email] by [code] — and the current address by [currentCode]
  /// when [requestEmailChange] sent it — then makes it the account's address,
  /// proven. The account answered is the signed-in one, updated.
  ///
  /// Refusals: the new code's `otp_invalid` · `otp_expired` · `otp_none` ·
  /// `otp_locked` (and `invalid_input`), the current code's same four
  /// prefixed `current_`, `email_taken` (another account proved it; the code
  /// is left for its owner), `email_unchanged`, `rate_limited`,
  /// `account_suspended`.
  Future<ApiResponse<User>> confirmEmailChange(
    String email,
    String code, {
    String? currentCode,
  });

  /// Permanently delete the signed-in user's account. Irreversible.
  Future<ApiResponse<void>> deleteAccount();

  // Pro auth overhaul (docs/design/pro-auth-social.md) — LOGIN-ONLY (a salon
  // is never auto-created; `provider_not_found` → one sentence, and no way to
  // register from here: docs/design/app-review-round-2.md §4).
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

  /// The Android Pro app's sign-up (docs/design/pro-android-signup.md §2.1,
  /// §5.2). Only the fenced Android code calls these, so the iOS program
  /// never does and its compiler drops them; the iOS binary read measures
  /// that (`/auth/provider/register` at 0, §8.3).
  ///
  /// Each runs the sign-in check with the identity first, then — only on
  /// `provider_not_found` — registers with **the same** proof:
  /// [ProviderSignUpSignedIn] on 200, [ProviderSignUpInvited] on 202,
  /// [ProviderSignUpCreated] on register's 201.
  Future<ProviderSignUpResult> signUpProviderWithGoogle(ProSignUpFields fields);
  Future<ProviderSignUpResult> signUpProviderWithEmail(
    String email,
    String code,
    ProSignUpFields fields,
  );

  /// Register only, with a proof already held: S4's « create my own salon
  /// instead » after the check surfaced invitations.
  Future<ProviderSignUpResult> registerProvider(
    InvitationProof proof,
    ProSignUpFields fields,
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
