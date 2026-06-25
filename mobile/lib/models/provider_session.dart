import 'provider_user.dart';

/// A persisted **provider** auth session: the access token (role `provider`),
/// the rotating [refreshToken] used to silently renew it, and the account it
/// belongs to. Kept separate from the consumer [Session] (different
/// secure-storage key) so a phone used as both consumer and provider on one
/// device doesn't overwrite the other. No client-side expiry — renewal is
/// 401-driven via `/auth/provider/refresh`.
class ProviderSession {
  final String token;
  final String? refreshToken;
  final ProviderUser provider;

  const ProviderSession({
    required this.token,
    required this.provider,
    this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
        'provider': provider.toJson(),
      };

  factory ProviderSession.fromJson(Map<String, dynamic> json) =>
      ProviderSession(
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String?,
        provider:
            ProviderUser.fromJson(json['provider'] as Map<String, dynamic>),
      );
}
