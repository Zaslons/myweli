import 'provider_user.dart';

/// A persisted **provider** auth session: the access token (role `provider`)
/// plus the account it belongs to. Kept separate from the consumer [Session]
/// (different secure-storage key) so a phone used as both consumer and provider
/// on one device doesn't overwrite the other. No client-side expiry — the
/// short-lived access token is refreshed server-side in a later slice.
class ProviderSession {
  final String token;
  final ProviderUser provider;

  const ProviderSession({required this.token, required this.provider});

  Map<String, dynamic> toJson() => {
        'token': token,
        'provider': provider.toJson(),
      };

  factory ProviderSession.fromJson(Map<String, dynamic> json) =>
      ProviderSession(
        token: json['token'] as String,
        provider:
            ProviderUser.fromJson(json['provider'] as Map<String, dynamic>),
      );
}
