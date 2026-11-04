import 'dart:async';
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:test/test.dart';

import 'apple_key.dart';
import 'apple_token_repository_contract.dart';

/// docs/design/backend-integrity-batch6.md §2.7, §13 (B6.7) — Sign in with
/// Apple's refresh token: exchanged from the sign-in's `authorizationCode`,
/// kept per account and client, revoked when the account is deleted — so a
/// deleted account leaves « Apps using Apple ID » (App Store 5.1.1(v)). With
/// no key configured, nothing is exchanged nor revoked, and nothing breaks.
void main() {
  final pair = appleTestKeyPair();
  final pem = applePkcs8Pem(pair.privateKey);
  final key = AppleSignInKey(
    teamId: 'TEAM123456',
    keyId: 'KEY1234567',
    privateKey: ECPrivateKey.raw(pair.privateKey),
  );
  final publicKey = ECPublicKey.raw(pair.publicKey);

  /// An Apple `id_token` as /auth/token returns it — unsigned here: the
  /// service reads its `sub` off a TLS answer from Apple, it does not verify.
  String appleIdToken(String sub) =>
      JWT({'sub': sub, 'aud': 'ci.myweli.app'}).sign(SecretKey('x'));

  /// The test key signs for every client these tests use. Choosing a key by
  /// client, and the boot rules, are apple_signin_keys_test.dart's.
  final keys = AppleSignInKeys.of({
    for (final c in ['ci.myweli.app', 'com.myweli.web', 'ci.myweli.pro'])
      c: key,
  });

  group('AppleSignInKey.fromPem — the .p8 as Apple gives it', () {
    test('as is, and with escaped newlines', () {
      for (final value in [pem, pem.replaceAll('\n', r'\n')]) {
        final k = AppleSignInKey.fromPem(
          teamId: 'TEAM123456',
          keyId: 'KEY1234567',
          pem: value,
        );
        final jwt = JWT.verify(k.clientSecret('ci.myweli.app'), publicKey);
        expect((jwt.payload as Map)['iss'], 'TEAM123456');
      }
    });

    test(
      'an unreadable key → StateError naming the variable, not the value',
      () {
        expect(
          () => AppleSignInKey.fromPem(
            teamId: 'TEAM123456',
            keyId: 'KEY1234567',
            pem: 'not a key',
            name: 'APPLE_APP_PRIVATE_KEY',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('APPLE_APP_PRIVATE_KEY'),
                isNot(contains('not a key')),
              ),
            ),
          ),
        );
      },
    );
  });

  test('the client_secret: ES256, kid, iss = team, sub = client, aud = Apple, '
      '5 minutes', () {
    final now = DateTime.utc(2026, 10, 21, 12);
    final secret = key.clientSecret('ci.myweli.app', now: now);
    final header =
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(secret.split('.').first)),
              ),
            )
            as Map;
    expect(header['alg'], 'ES256');
    expect(header['kid'], 'KEY1234567');
    final jwt = JWT.verify(
      secret,
      publicKey,
      checkExpiresIn: false,
      checkNotBefore: false,
    );
    final claims = jwt.payload as Map;
    expect(claims['iss'], 'TEAM123456');
    expect(claims['sub'], 'ci.myweli.app');
    expect(claims['aud'], 'https://appleid.apple.com');
    final iat = claims['iat'] as int;
    expect(iat, now.millisecondsSinceEpoch ~/ 1000);
    expect(claims['exp'], iat + 300);
  });

  group('InMemoryAppleTokenRepository — the twin contract', () {
    appleTokenRepositoryContract(
      repo: InMemoryAppleTokenRepository.new,
      id: (name) => 'acc-$name',
    );
  });

  group('keepFromCode — at sign-in', () {
    late InMemoryAppleTokenRepository repo;
    late List<http.Request> sent;
    late List<String> logs;

    setUp(() {
      repo = InMemoryAppleTokenRepository();
      sent = [];
      logs = [];
    });

    AppleTokenService service(
      Future<http.Response> Function(http.Request) answer, {
      bool noKey = false,
      Duration timeout = const Duration(seconds: 5),
    }) => AppleTokenService(
      repo,
      noKey ? AppleSignInKeys.none : keys,
      client: MockClient((req) async {
        sent.add(req);
        return answer(req);
      }),
      log: logs.add,
      timeout: timeout,
    );

    Future<http.Response> granted(
      http.Request _, {
      String sub = 'apple-sub',
    }) async => http.Response(
      jsonEncode({
        'access_token': 'a',
        'refresh_token': 'rt-secret-1',
        'id_token': appleIdToken(sub),
        'token_type': 'Bearer',
      }),
      200,
    );

    Future<void> keep(AppleTokenService s, {String? redirectUri}) =>
        s.keepFromCode(
          kind: 'user',
          accountId: 'user_1',
          clientId: 'ci.myweli.app',
          sub: 'apple-sub',
          code: 'code-secret-1',
          redirectUri: redirectUri,
        );

    test(
      'exchanged with the token\'s audience, kept for the account',
      () async {
        await keep(service(granted));
        expect(
          sent.single.url.toString(),
          'https://appleid.apple.com/auth/token',
        );
        expect(sent.single.method, 'POST');
        final form = sent.single.bodyFields;
        expect(form['client_id'], 'ci.myweli.app');
        expect(form['code'], 'code-secret-1');
        expect(form['grant_type'], 'authorization_code');
        expect(form.containsKey('redirect_uri'), isFalse);
        final secret = JWT.verify(form['client_secret']!, publicKey);
        expect((secret.payload as Map)['sub'], 'ci.myweli.app');
        expect(await repo.listFor(kind: 'user', accountId: 'user_1'), [
          (clientId: 'ci.myweli.app', refreshToken: 'rt-secret-1'),
        ]);
      },
    );

    test('the web\'s code goes with its redirect_uri', () async {
      await keep(service(granted), redirectUri: 'https://myweli.com/connexion');
      expect(
        sent.single.bodyFields['redirect_uri'],
        'https://myweli.com/connexion',
      );
    });

    test('a later sign-in replaces the token for that client', () async {
      await keep(service(granted));
      await keep(
        service(
          (_) async => http.Response(
            jsonEncode({
              'refresh_token': 'rt-secret-2',
              'id_token': appleIdToken('apple-sub'),
            }),
            200,
          ),
        ),
      );
      expect(await repo.listFor(kind: 'user', accountId: 'user_1'), [
        (clientId: 'ci.myweli.app', refreshToken: 'rt-secret-2'),
      ]);
    });

    test('Apple\'s id_token names SOMEONE ELSE → nothing kept (another '
        'person\'s code never lands under this account)', () async {
      await keep(service((r) => granted(r, sub: 'other-sub')));
      expect(await repo.listFor(kind: 'user', accountId: 'user_1'), isEmpty);
      expect(logs.single, contains('apple_token FAILED'));
      expect(logs.single, contains('sub_mismatch'));
    });

    test('Apple refuses (400) → nothing kept, a log line, no throw', () async {
      await keep(
        service((_) async => http.Response('{"error":"invalid_grant"}', 400)),
      );
      expect(await repo.listFor(kind: 'user', accountId: 'user_1'), isEmpty);
      expect(logs.single, contains('apple_token FAILED'));
      expect(logs.single, contains('status=400'));
      expect(logs.single, contains('error=invalid_grant'));
      expect(logs.single, contains('client=ci.myweli.app'));
    });

    test('a key that does not cover the client says invalid_client — the '
        'one answer that tests a key (apple-signin-keys.md §9) — and nothing '
        'else of Apple\'s answer is logged', () async {
      await keep(
        service(
          (_) async => http.Response(
            '{"error":"invalid_client","error_description":"rt-secret-1 '
            'code-secret-1"}',
            400,
          ),
        ),
      );
      expect(logs.single, contains('error=invalid_client'));
      expect(logs.single, isNot(contains('rt-secret-1')));
      expect(logs.single, isNot(contains('code-secret-1')));
      expect(logs.single, isNot(contains('error_description')));
    });

    test('no answer / a throw → nothing kept, no throw', () async {
      await keep(service((_) async => throw http.ClientException('reset')));
      expect(await repo.listFor(kind: 'user', accountId: 'user_1'), isEmpty);
      expect(logs.single, contains('apple_token FAILED'));
    });

    test(
      'Apple slower than the bound → given up, the sign-in is not held',
      () async {
        final never = Completer<http.Response>();
        final s = service(
          (_) => never.future,
          timeout: const Duration(milliseconds: 50),
        );
        await keep(s).timeout(const Duration(seconds: 2));
        expect(await repo.listFor(kind: 'user', accountId: 'user_1'), isEmpty);
        expect(logs.single, contains('apple_token FAILED'));
      },
    );

    test('no key → no call to Apple, nothing kept, a SKIPPED line', () async {
      await keep(service(granted, noKey: true));
      expect(sent, isEmpty);
      expect(await repo.listFor(kind: 'user', accountId: 'user_1'), isEmpty);
      expect(logs.single, contains('apple_token SKIPPED'));
    });

    test('no log line ever carries the code or the token', () async {
      await keep(service((r) => granted(r, sub: 'other-sub')));
      await keep(service((_) async => http.Response('{}', 400)));
      for (final line in logs) {
        expect(line, isNot(contains('code-secret-1')));
        expect(line, isNot(contains('rt-secret-1')));
      }
    });
  });

  group('revokeAll — at deletion', () {
    late InMemoryAppleTokenRepository repo;
    late List<http.Request> sent;
    late List<String> logs;

    setUp(() async {
      repo = InMemoryAppleTokenRepository();
      sent = [];
      logs = [];
      await repo.keep(
        kind: 'user',
        accountId: 'acc',
        clientId: 'ci.myweli.app',
        refreshToken: 'rt-app',
      );
      await repo.keep(
        kind: 'user',
        accountId: 'acc',
        clientId: 'com.myweli.web',
        refreshToken: 'rt-web',
      );
      // The same id string under the OTHER kind, and another account: kept.
      await repo.keep(
        kind: 'provider',
        accountId: 'acc',
        clientId: 'ci.myweli.pro',
        refreshToken: 'rt-pro',
      );
      await repo.keep(
        kind: 'user',
        accountId: 'other',
        clientId: 'ci.myweli.app',
        refreshToken: 'rt-other',
      );
    });

    AppleTokenService service(
      Future<http.Response> Function(http.Request) answer, {
      bool noKey = false,
    }) => AppleTokenService(
      repo,
      noKey ? AppleSignInKeys.none : keys,
      client: MockClient((req) async {
        sent.add(req);
        return answer(req);
      }),
      log: logs.add,
    );

    test('every token of the account is revoked with its own client, then '
        'none is left', () async {
      await service(
        (_) async => http.Response('', 200),
      ).revokeAll(kind: 'user', accountId: 'acc');
      expect(sent, hasLength(2));
      final byToken = {for (final r in sent) r.bodyFields['token']: r};
      expect(byToken.keys, unorderedEquals(['rt-app', 'rt-web']));
      for (final r in sent) {
        expect(r.url.toString(), 'https://appleid.apple.com/auth/revoke');
        expect(r.bodyFields['token_type_hint'], 'refresh_token');
        final client = r.bodyFields['client_id']!;
        final secret = JWT.verify(r.bodyFields['client_secret']!, publicKey);
        expect((secret.payload as Map)['sub'], client);
      }
      expect(byToken['rt-app']!.bodyFields['client_id'], 'ci.myweli.app');
      expect(byToken['rt-web']!.bodyFields['client_id'], 'com.myweli.web');
      expect(await repo.listFor(kind: 'user', accountId: 'acc'), isEmpty);
    });

    test('the other kind and other accounts keep theirs', () async {
      await service(
        (_) async => http.Response('', 200),
      ).revokeAll(kind: 'user', accountId: 'acc');
      expect(
        await repo.listFor(kind: 'provider', accountId: 'acc'),
        hasLength(1),
      );
      expect(
        await repo.listFor(kind: 'user', accountId: 'other'),
        hasLength(1),
      );
    });

    test('Apple fails → the rows are erased all the same, a log line, no '
        'throw (the deletion goes on)', () async {
      await service(
        (_) async => http.Response('', 503),
      ).revokeAll(kind: 'user', accountId: 'acc');
      expect(await repo.listFor(kind: 'user', accountId: 'acc'), isEmpty);
      expect(
        logs.where((l) => l.contains('apple_revoke FAILED')),
        hasLength(2),
      );
      for (final line in logs) {
        expect(line, isNot(contains('rt-')));
      }
    });

    test('Apple refuses a revocation → its error word in the line', () async {
      await service(
        (_) async => http.Response('{"error":"invalid_client"}', 400),
      ).revokeAll(kind: 'user', accountId: 'acc');
      expect(
        logs.where((l) => l.contains('apple_revoke FAILED')),
        everyElement(contains('error=invalid_client')),
      );
    });

    test('a throw → erased all the same', () async {
      await service(
        (_) async => throw http.ClientException('reset'),
      ).revokeAll(kind: 'user', accountId: 'acc');
      expect(await repo.listFor(kind: 'user', accountId: 'acc'), isEmpty);
    });

    test('no key → no call, the rows erased, a SKIPPED line', () async {
      await service(
        (_) async => http.Response('', 200),
        noKey: true,
      ).revokeAll(kind: 'user', accountId: 'acc');
      expect(sent, isEmpty);
      expect(await repo.listFor(kind: 'user', accountId: 'acc'), isEmpty);
      expect(logs.single, contains('apple_revoke SKIPPED'));
    });

    test('nothing kept → no call, no line', () async {
      await service(
        (_) async => http.Response('', 200),
      ).revokeAll(kind: 'user', accountId: 'nobody');
      expect(sent, isEmpty);
      expect(logs, isEmpty);
    });
  });

  group('appleErrorWord — only a short word of Apple\'s answer is logged', () {
    test('the error word', () {
      expect(appleErrorWord('{"error":"invalid_client"}'), 'invalid_client');
      expect(appleErrorWord('{"error":"invalid_grant"}'), 'invalid_grant');
    });

    test('anything else → « - »', () {
      expect(appleErrorWord('<html>'), '-');
      expect(appleErrorWord(''), '-');
      expect(appleErrorWord('{}'), '-');
      expect(appleErrorWord('{"error":12}'), '-');
      expect(appleErrorWord('[1]'), '-');
      expect(appleErrorWord('{"error":"Not A Word, rt-secret"}'), '-');
      expect(appleErrorWord('{"error":"${'a' * 41}"}'), '-');
    });
  });

  group('appleCodeOf — the optional fields of a sign-in body', () {
    test('a code, and an https redirect', () {
      final c = appleCodeOf({
        'authorizationCode': ' abc ',
        'redirectUri': 'https://myweli.com/connexion',
      });
      expect(c.code, 'abc');
      expect(c.redirectUri, 'https://myweli.com/connexion');
    });

    test('absent, empty, not a string or too long → no code', () {
      expect(appleCodeOf({}).code, isNull);
      expect(appleCodeOf({'authorizationCode': ''}).code, isNull);
      expect(appleCodeOf({'authorizationCode': 'x' * 2001}).code, isNull);
    });

    test('a wrong JSON type → BodyFieldTypeError (400 invalid_body, like '
        'every field — read before the sign-in)', () {
      expect(
        () => appleCodeOf({'authorizationCode': 12}),
        throwsA(isA<BodyFieldTypeError>()),
      );
      expect(
        () => appleCodeOf({'authorizationCode': 'abc', 'redirectUri': 1}),
        throwsA(isA<BodyFieldTypeError>()),
      );
    });

    test('a redirect that is not https, or too long → dropped', () {
      expect(
        appleCodeOf({
          'authorizationCode': 'abc',
          'redirectUri': 'http://myweli.com/connexion',
        }).redirectUri,
        isNull,
      );
      expect(
        appleCodeOf({
          'authorizationCode': 'abc',
          'redirectUri': 'https://${'x' * 300}.com',
        }).redirectUri,
        isNull,
      );
    });
  });
}
