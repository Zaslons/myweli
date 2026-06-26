import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

/// Supplies a Google OAuth2 access token for FCM. Behind an interface so the
/// `messages:send` path is testable without service-account creds.
/// Design: docs/design/push-notifications-fcm.md §3.
abstract interface class AccessTokenSource {
  Future<String?> token();
}

/// Mints + caches a token from a Firebase **service account** (RS256 JWT →
/// `oauth2.googleapis.com/token`). Constructed from env; never logs the key.
class ServiceAccountTokenSource implements AccessTokenSource {
  ServiceAccountTokenSource({
    required this.clientEmail,
    required this.privateKeyPem,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _scope = 'https://www.googleapis.com/auth/firebase.messaging';

  final String clientEmail;
  final String privateKeyPem;
  final http.Client _client;

  String? _cached;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<String?> token() async {
    final now = DateTime.now().toUtc();
    if (_cached != null && now.isBefore(_expiresAt)) return _cached;
    try {
      final assertion = JWT({
        'iss': clientEmail,
        'scope': _scope,
        'aud': _tokenUrl,
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      }).sign(RSAPrivateKey(privateKeyPem), algorithm: JWTAlgorithm.RS256);

      final res = await _client.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': assertion,
        },
      );
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final token = json['access_token'] as String?;
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
      _cached = token;
      // Refresh a minute early to avoid edge-of-expiry failures.
      _expiresAt = now.add(Duration(seconds: expiresIn - 60));
      return token;
    } catch (_) {
      return null;
    }
  }
}
