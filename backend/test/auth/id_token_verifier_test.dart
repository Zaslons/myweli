import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/jwks_cache.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:test/test.dart';

/// Deterministic RSA keypair for signing test tokens (2048-bit).
pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey> _generate(int seed) {
  final random = pc.FortunaRandom()
    ..seed(
      pc.KeyParameter(
        Uint8List.fromList(List.generate(32, (i) => (i + seed) % 256)),
      ),
    );
  final generator = pc.RSAKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        random,
      ),
    );
  final pair = generator.generateKeyPair();
  return pc.AsymmetricKeyPair(
    pair.publicKey as pc.RSAPublicKey,
    pair.privateKey as pc.RSAPrivateKey,
  );
}

String _b64BigInt(BigInt v) {
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = <int>[
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return base64Url.encode(bytes).replaceAll('=', '');
}

void main() {
  final keyA = _generate(1);
  final keyB = _generate(2);

  String jwks(Map<String, pc.RSAPublicKey> keys) => jsonEncode({
    'keys': [
      for (final e in keys.entries)
        {
          'kty': 'RSA',
          'alg': 'RS256',
          'use': 'sig',
          'kid': e.key,
          'n': _b64BigInt(e.value.modulus!),
          'e': _b64BigInt(e.value.publicExponent!),
        },
    ],
  });

  /// A JWKS endpoint serving [byFetch] — the Nth fetch returns the Nth map
  /// (last one repeats), so key rotation is testable.
  http.Client jwksClient(List<Map<String, pc.RSAPublicKey>> byFetch) {
    var fetch = 0;
    return MockClient((req) async {
      final keys = byFetch[fetch.clamp(0, byFetch.length - 1)];
      fetch++;
      return http.Response(
        jwks(keys),
        200,
        headers: {'cache-control': 'max-age=3600'},
      );
    });
  }

  String sign(
    Map<String, dynamic> payload, {
    required pc.RSAPrivateKey key,
    String kid = 'k1',
    Duration? expiresIn = const Duration(hours: 1),
  }) {
    final jwt = JWT(payload, header: {'kid': kid});
    return jwt.sign(
      RSAPrivateKey.raw(key),
      algorithm: JWTAlgorithm.RS256,
      expiresIn: expiresIn,
    );
  }

  Map<String, dynamic> googleClaims({bool verified = true}) => {
    'iss': 'https://accounts.google.com',
    'aud': 'client-web',
    'sub': 'g-sub-1',
    'email': 'Ama@Example.com',
    'email_verified': verified,
    'name': 'Ama K',
    'picture': 'https://p.example/ama.png',
  };

  GoogleIdTokenVerifier google(
    http.Client client, {
    List<String> ids = const ['client-web', 'client-android'],
  }) => GoogleIdTokenVerifier(
    clientIds: ids,
    jwks: JwksCache(
      'https://jwks.test/certs',
      client: client,
      minRefetchInterval: Duration.zero,
    ),
  );

  test('valid Google token → verified claims (email lowercased)', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    final res = await v.verify(sign(googleClaims(), key: keyA.privateKey));
    expect(res.ok, isTrue);
    expect(res.sub, 'g-sub-1');
    expect(res.email, 'ama@example.com');
    expect(res.emailVerified, isTrue);
    expect(res.name, 'Ama K');
    expect(res.avatarUrl, 'https://p.example/ama.png');
  });

  test(
    'Google token with an SDK-minted nonce and no caller nonce → ok '
    '(the iOS Google Sign-In SDK adds + self-validates its own nonce)',
    () async {
      final v = google(
        jwksClient([
          {'k1': keyA.publicKey},
        ]),
      );
      final res = await v.verify(
        sign({
          ...googleClaims(),
          'nonce': 'ios-sdk-minted',
        }, key: keyA.privateKey),
      );
      expect(res.ok, isTrue);
      expect(res.sub, 'g-sub-1');
    },
  );

  test('Google: a caller-presented nonce must still MATCH the claim', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    final res = await v.verify(
      sign({...googleClaims(), 'nonce': 'other'}, key: keyA.privateKey),
      nonce: 'expected',
    );
    expect(res.ok, isFalse);
    expect(res.error, 'token_rejected');
  });

  test('signature from a different key → token_rejected', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    final res = await v.verify(sign(googleClaims(), key: keyB.privateKey));
    expect(res.ok, isFalse);
    expect(res.error, 'token_rejected');
  });

  test('wrong audience → token_rejected', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    final res = await v.verify(
      sign({...googleClaims(), 'aud': 'evil'}, key: keyA.privateKey),
    );
    expect(res.error, 'token_rejected');
  });

  test('wrong issuer → token_rejected', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    final res = await v.verify(
      sign({
        ...googleClaims(),
        'iss': 'https://evil.test',
      }, key: keyA.privateKey),
    );
    expect(res.error, 'token_rejected');
  });

  test('expired token → token_rejected', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    final expired = {
      ...googleClaims(),
      'exp':
          DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
    };
    final res = await v.verify(
      sign(expired, key: keyA.privateKey, expiresIn: null),
    );
    expect(res.error, 'token_rejected');
  });

  test('google requires a verified email → token_rejected', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    final res = await v.verify(
      sign(googleClaims(verified: false), key: keyA.privateKey),
    );
    expect(res.error, 'token_rejected');
  });

  test('malformed / non-RS256 → invalid_token', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
    );
    expect((await v.verify('not-a-jwt')).error, 'invalid_token');
    final hs = JWT(googleClaims()).sign(SecretKey('s'));
    expect((await v.verify(hs)).error, 'invalid_token');
  });

  test('no configured audiences → verifier_not_configured', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
      ]),
      ids: const [],
    );
    final res = await v.verify(sign(googleClaims(), key: keyA.privateKey));
    expect(res.error, 'verifier_not_configured');
  });

  test('key rotation: unknown kid triggers a refetch', () async {
    final v = google(
      jwksClient([
        {'k1': keyA.publicKey},
        {'k1': keyA.publicKey, 'k2': keyB.publicKey},
      ]),
    );
    // Warm the cache with the first set (k1 only).
    expect(
      (await v.verify(sign(googleClaims(), key: keyA.privateKey))).ok,
      isTrue,
    );
    // k2-signed token → refetch picks up the rotated key.
    final res = await v.verify(
      sign(googleClaims(), key: keyB.privateKey, kid: 'k2'),
    );
    expect(res.ok, isTrue);
  });

  group('apple nonce', () {
    Map<String, dynamic> appleClaims({String? nonce}) => {
      'iss': 'https://appleid.apple.com',
      'aud': 'com.myweli.app',
      'sub': 'a-sub-1',
      'email': 'relay@privaterelay.appleid.com',
      'email_verified': 'true',
      if (nonce != null) 'nonce': nonce,
    };

    AppleIdTokenVerifier apple(http.Client client) => AppleIdTokenVerifier(
      clientIds: const ['com.myweli.app'],
      jwks: JwksCache(
        'https://jwks.test/apple',
        client: client,
        minRefetchInterval: Duration.zero,
      ),
    );

    test('raw nonce match → ok (apple email counts verified)', () async {
      final v = apple(
        jwksClient([
          {'k1': keyA.publicKey},
        ]),
      );
      final res = await v.verify(
        sign(appleClaims(nonce: 'raw-nonce'), key: keyA.privateKey),
        nonce: 'raw-nonce',
      );
      expect(res.ok, isTrue);
      expect(res.emailVerified, isTrue);
    });

    test('sha256(nonce) claim (iOS convention) → ok', () async {
      final hashed = c.sha256.convert(utf8.encode('raw-nonce')).toString();
      final v = apple(
        jwksClient([
          {'k1': keyA.publicKey},
        ]),
      );
      final res = await v.verify(
        sign(appleClaims(nonce: hashed), key: keyA.privateKey),
        nonce: 'raw-nonce',
      );
      expect(res.ok, isTrue);
    });

    test('nonce mismatch → token_rejected', () async {
      final v = apple(
        jwksClient([
          {'k1': keyA.publicKey},
        ]),
      );
      final res = await v.verify(
        sign(appleClaims(nonce: 'other'), key: keyA.privateKey),
        nonce: 'raw-nonce',
      );
      expect(res.error, 'token_rejected');
    });

    test('token carries a nonce but none provided → token_rejected', () async {
      final v = apple(
        jwksClient([
          {'k1': keyA.publicKey},
        ]),
      );
      final res = await v.verify(
        sign(appleClaims(nonce: 'raw-nonce'), key: keyA.privateKey),
      );
      expect(res.error, 'token_rejected');
    });
  });
}
