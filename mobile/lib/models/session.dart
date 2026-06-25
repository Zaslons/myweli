import 'user.dart';

/// A persisted auth session. [token] is the access JWT; [refreshToken] is the
/// rotating opaque token used to silently renew it (null for legacy sessions
/// saved before silent refresh existed). [expiresAt] is null when the session
/// has no client-side expiry (valid until logout — renewal is 401-driven, not
/// clock-driven).
class Session {
  final String token;
  final String? refreshToken;
  final User user;
  final DateTime? expiresAt;

  const Session({
    required this.token,
    required this.user,
    this.refreshToken,
    this.expiresAt,
  });

  bool isExpired(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
        'user': user.toJson(),
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String?,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
      );
}
