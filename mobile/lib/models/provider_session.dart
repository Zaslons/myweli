import 'pro_membership.dart';
import 'provider_user.dart';

/// A persisted **provider** auth session: the access token (role `provider`),
/// the rotating [refreshToken] used to silently renew it, and the account it
/// belongs to. Kept separate from the consumer [Session] (different
/// secure-storage key) so a phone used as both consumer and provider on one
/// device doesn't overwrite the other. No client-side expiry — renewal is
/// 401-driven via `/auth/provider/refresh`.
///
/// [membership] (team access R4b) caches the last-fetched role/capabilities
/// so the app shapes correctly on the FIRST cold-start frame; it is refreshed
/// from `GET /me/provider` on every start (never trusted long-term — the
/// server resolves per request, T38).
class ProviderSession {
  final String token;
  final String? refreshToken;
  final ProviderUser provider;
  final ProMembership? membership;

  const ProviderSession({
    required this.token,
    required this.provider,
    this.refreshToken,
    this.membership,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
        'provider': provider.toJson(),
        if (membership != null) 'membership': membership!.toJson(),
      };

  factory ProviderSession.fromJson(Map<String, dynamic> json) =>
      ProviderSession(
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String?,
        provider:
            ProviderUser.fromJson(json['provider'] as Map<String, dynamic>),
        // Legacy sessions (pre-R4b) simply have no cached membership.
        membership: json['membership'] == null
            ? null
            : ProMembership.fromJson(
                json['membership'] as Map<String, dynamic>,
              ),
      );
}
