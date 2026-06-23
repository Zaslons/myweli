import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// A freshly issued access token + its expiry.
typedef AccessToken = ({String token, DateTime expiresAt});

/// Issues and verifies auth tokens (docs/BACKEND.md §3.1):
///   - **access**: short-lived signed JWT (HS256), verified statelessly;
///   - **refresh**: opaque random — only its SHA-256 hash is ever stored.
class TokenService {
  TokenService({
    required String secret,
    this.accessTtl = const Duration(minutes: 15),
  }) : _secret = SecretKey(secret);

  final SecretKey _secret;
  final Duration accessTtl;
  final Random _random = Random.secure();

  /// Signed access JWT carrying `sub`, `role`, `jti`, `iat`, `exp`.
  AccessToken issueAccessToken({
    required String subject,
    required String role,
  }) {
    final expiresAt = DateTime.now().toUtc().add(accessTtl);
    final jwt = JWT({'role': role, 'jti': _randomBase64(16)}, subject: subject);
    return (
      token: jwt.sign(_secret, expiresIn: accessTtl),
      expiresAt: expiresAt,
    );
  }

  /// The verified payload, or `null` for any invalid/expired/tampered token.
  JWT? verifyAccessToken(String token) {
    try {
      return JWT.verify(token, _secret);
    } on JWTException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// A new opaque refresh token. Return it to the client once; persist only
  /// [hashToken] of it.
  String generateRefreshToken() => _randomBase64(32);

  /// SHA-256 hex of a token — what we store for refresh tokens (and OTPs).
  String hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  String _randomBase64(int bytes) =>
      base64Url.encode(List<int>.generate(bytes, (_) => _random.nextInt(256)));
}
