import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/auth/apple_key_probe.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:test/test.dart';

import 'apple_key.dart';

/// docs/design/apple-signin-keys.md §5, §9 step 2 — before a key is deployed,
/// ask Apple whether it covers each client: a deliberately invalid code gets
/// `invalid_grant` when Apple accepted our client secret (the code is what it
/// refused), `invalid_client` when this key does not cover that client.
/// Anything else is « unknown » — never read as a pass.
void main() {
  final pair = appleTestKeyPair();
  final key = AppleSignInKey.fromPem(
    teamId: 'TEAM123456',
    keyId: 'KEY1234567',
    pem: applePkcs8Pem(pair.privateKey),
  );
  final publicKey = ECPublicKey.raw(pair.publicKey);

  late List<http.Request> sent;
  setUp(() => sent = []);

  Future<AppleKeyProbe> probe(
    Future<http.Response> Function(http.Request) answer, {
    String clientId = 'com.myweli.pro',
  }) => probeAppleKey(
    key,
    clientId,
    client: MockClient((req) async {
      sent.add(req);
      return answer(req);
    }),
  );

  test('asks /auth/token with an invalid code and a secret for the client, '
      'signed by the key', () async {
    await probe((_) async => http.Response('{"error":"invalid_grant"}', 400));
    final r = sent.single;
    expect(r.url.toString(), 'https://appleid.apple.com/auth/token');
    expect(r.method, 'POST');
    expect(r.bodyFields['client_id'], 'com.myweli.pro');
    expect(r.bodyFields['grant_type'], 'authorization_code');
    expect(r.bodyFields['code'], isNotEmpty);
    final secret = JWT.verify(r.bodyFields['client_secret']!, publicKey);
    expect((secret.payload as Map)['sub'], 'com.myweli.pro');
    expect(
      JWT.decode(r.bodyFields['client_secret']!).header!['kid'],
      'KEY1234567',
    );
  });

  test('invalid_grant → covered', () async {
    final p = await probe(
      (_) async => http.Response('{"error":"invalid_grant"}', 400),
    );
    expect(p.coverage, AppleKeyCoverage.covered);
    expect(p.clientId, 'com.myweli.pro');
    expect(p.answer, contains('invalid_grant'));
  });

  test('invalid_client → not covered', () async {
    final p = await probe(
      (_) async => http.Response('{"error":"invalid_client"}', 400),
    );
    expect(p.coverage, AppleKeyCoverage.notCovered);
  });

  for (final (label, response) in [
    ('a 200 (a bogus code must never be granted)', http.Response('{}', 200)),
    ('a 500', http.Response('oops', 500)),
    ('another error word', http.Response('{"error":"unsupported"}', 400)),
    ('a body that is not JSON', http.Response('<html>', 400)),
  ]) {
    test('$label → unknown, never a pass', () async {
      final p = await probe((_) async => response);
      expect(p.coverage, AppleKeyCoverage.unknown);
    });
  }

  test('no answer → unknown, no throw', () async {
    final p = await probe((_) async => throw http.ClientException('reset'));
    expect(p.coverage, AppleKeyCoverage.unknown);
  });

  test('the line printed for a probe carries the client and Apple\'s word, '
      'never the secret', () async {
    await probe((_) async => http.Response('{"error":"invalid_grant"}', 400));
    final secret = sent.single.bodyFields['client_secret']!;
    final p = await probe(
      (_) async => http.Response(
        '{"error":"invalid_client","error_description":"$secret"}',
        400,
      ),
    );
    final line = describeAppleKeyProbe(p);
    expect(line, contains('com.myweli.pro'));
    expect(line, contains('invalid_client'));
    expect(line, isNot(contains(secret)));
    expect(line, isNot(contains(secret.split('.').last)));
  });
}
