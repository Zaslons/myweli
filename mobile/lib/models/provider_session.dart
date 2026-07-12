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

  /// R6 multi-salons: the salon the user last SWITCHED to (null = the
  /// default). Restored at cold start and revalidated by the first
  /// `GET /me/provider?salonId=` — a 403 silently falls back to default.
  final String? selectedSalonId;

  const ProviderSession({
    required this.token,
    required this.provider,
    this.refreshToken,
    this.membership,
    this.selectedSalonId,
  });

  ProviderSession copyWith({
    ProMembership? membership,
    String? selectedSalonId,
    bool clearSelectedSalon = false,
  }) =>
      ProviderSession(
        token: token,
        refreshToken: refreshToken,
        provider: provider,
        membership: membership ?? this.membership,
        selectedSalonId: clearSelectedSalon
            ? null
            : (selectedSalonId ?? this.selectedSalonId),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
        'provider': provider.toJson(),
        if (membership != null) 'membership': membership!.toJson(),
        if (selectedSalonId != null) 'selectedSalonId': selectedSalonId,
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
        // Legacy sessions (pre-R6) simply have no selection.
        selectedSalonId: json['selectedSalonId'] as String?,
      );
}
