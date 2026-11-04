import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// docs/design/backend-integrity-batch6.md §13 (B6.7) — the app's three Apple
/// doors (client sign-in, Pro sign-in, Pro sign-up) send Apple's one-time
/// `authorizationCode` with the identity token: the server exchanges it for
/// the refresh token it revokes when the account is deleted (App Store
/// 5.1.1(v)). No redirect URI from the app — a native code needs none.
void main() {
  Map<String, dynamic> providerJson() => {
    'id': 'provider_1',
    'phoneNumber': '+2250707010101',
    'name': null,
    'businessName': 'Élégance',
    'businessType': 'salon',
    'email': null,
    'address': null,
    'verificationStatus': 'pending',
    'rejectionReason': null,
    'kycDocs': const <Map<String, dynamic>>[],
    'createdAt': DateTime(2026).toIso8601String(),
    'providerId': 'provider1',
  };

  http.Response clientSession() => http.Response(
    jsonEncode({
      'tokens': {
        'accessToken': 'access-123',
        'refreshToken': 'refresh-123',
        'expiresAt': DateTime(2026).toIso8601String(),
      },
      'user': {
        'id': 'user_1',
        'phoneNumber': null,
        'name': null,
        'email': null,
        'avatarUrl': null,
        'createdAt': DateTime(2026).toIso8601String(),
      },
    }),
    200,
  );

  http.Response proSession(int status) => http.Response(
    jsonEncode({
      'accessToken': 'access-123',
      'refreshToken': 'refresh-123',
      'provider': providerJson(),
    }),
    status,
  );

  /// The credential Apple's sheet hands back; [hashedNonces] records what
  /// Apple was asked to sign.
  AppleCredentialProvider apple(
    List<String> hashedNonces, {
    String code = 'apple-code',
  }) => (hashedNonce) async {
    hashedNonces.add(hashedNonce);
    return AuthorizationCredentialAppleID(
      userIdentifier: 'apple-user',
      givenName: null,
      familyName: null,
      authorizationCode: code,
      email: null,
      identityToken: 'apple-identity-token',
      state: null,
    );
  };

  Future<(Map<String, dynamic>, List<String>)> run(
    String path,
    http.Response answer,
    Future<Object?> Function(ApiAuthService s) call, {
    String code = 'apple-code',
  }) async {
    Map<String, dynamic>? sent;
    final nonces = <String>[];
    final service = ApiAuthService(
      client: MockClient((req) async {
        expect(req.url.path, path);
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return answer;
      }),
      baseUrl: 'http://x',
      appleCredential: apple(nonces, code: code),
    );
    await call(service);
    return (sent!, nonces);
  }

  test('client sign-in: the code crosses, with the token and the raw '
      'nonce whose SHA-256 Apple signed', () async {
    final (sent, nonces) = await run(
      '/auth/apple',
      clientSession(),
      (s) => s.signInWithApple(),
    );
    expect(sent['identityToken'], 'apple-identity-token');
    expect(sent['authorizationCode'], 'apple-code');
    expect(sent.containsKey('redirectUri'), isFalse);
    final raw = sent['nonce'] as String;
    expect(nonces.single, sha256.convert(utf8.encode(raw)).toString());
  });

  test('Pro sign-in: the code crosses', () async {
    final (sent, _) = await run(
      '/auth/provider/apple',
      proSession(200),
      (s) => s.signInProviderWithApple(),
    );
    expect(sent['identityToken'], 'apple-identity-token');
    expect(sent['authorizationCode'], 'apple-code');
  });

  test('an empty code is not sent — the sign-in as before', () async {
    final (sent, _) = await run(
      '/auth/apple',
      clientSession(),
      (s) => s.signInWithApple(),
      code: '',
    );
    expect(sent.containsKey('authorizationCode'), isFalse);
    expect(sent['identityToken'], 'apple-identity-token');
  });
}
