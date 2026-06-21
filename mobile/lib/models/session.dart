import 'user.dart';

/// A persisted auth session. The token is a placeholder the backend will
/// replace with a real (access/refresh) JWT. [expiresAt] is null when the
/// session has no client-side expiry (valid until logout).
class Session {
  final String token;
  final User user;
  final DateTime? expiresAt;

  const Session({
    required this.token,
    required this.user,
    this.expiresAt,
  });

  bool isExpired(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
        'token': token,
        'user': user.toJson(),
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
      );
}
