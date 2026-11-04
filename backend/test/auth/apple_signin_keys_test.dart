import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:test/test.dart';

import 'apple_key.dart';

/// docs/design/apple-signin-keys.md — MyWeli and MyWeli Pro are separate Sign
/// in with Apple primaries, and Apple's model is a key per primary. The server
/// holds one key per app (`APPLE_APP_*`, `APPLE_PRO_*`), each listing the
/// clients it signs for, and picks the key by the token's client. §4 is the
/// contract these tests hold.
void main() {
  const clients = ['com.myweli.app', 'com.myweli.pro', 'com.myweli.signin'];

  final appPair = appleTestKeyPair();
  final proPair = appleTestKeyPair(11);
  final appPem = applePkcs8Pem(appPair.privateKey);
  final proPem = applePkcs8Pem(proPair.privateKey);
  final appPublic = ECPublicKey.raw(appPair.publicKey);
  final proPublic = ECPublicKey.raw(proPair.publicKey);

  String? Function(String) env(Map<String, String> m) =>
      (k) => m[k];

  /// Both slots, the web's Services ID under the MyWeli primary.
  Map<String, String> both() => {
    'APPLE_TEAM_ID': 'TEAM123456',
    'APPLE_APP_KEY_ID': 'APPKEY0001',
    'APPLE_APP_PRIVATE_KEY': appPem,
    'APPLE_APP_KEY_CLIENTS': 'com.myweli.app,com.myweli.signin',
    'APPLE_PRO_KEY_ID': 'PROKEY0001',
    'APPLE_PRO_PRIVATE_KEY': proPem,
    'APPLE_PRO_KEY_CLIENTS': 'com.myweli.pro',
  };

  AppleSignInKeys load(Map<String, String> m) =>
      AppleSignInKeys.fromEnv(env(m), clientIds: clients);

  /// The `kid` a client secret carries — which key signed it.
  String kidOf(String secret) => JWT.decode(secret).header!['kid'] as String;

  group('AppleSignInKeys.fromEnv — §4, the boot rules', () {
    test('rule 1: no key variable at all → inactive, nothing refused', () {
      final keys = load({});
      expect(keys.isActive, isFalse);
      expect(keys.forClient('com.myweli.app'), isNull);
    });

    test('a lone APPLE_TEAM_ID → still inactive', () {
      expect(load({'APPLE_TEAM_ID': 'TEAM123456'}).isActive, isFalse);
    });

    test('both slots → each client resolves to its own slot\'s key', () {
      final keys = load(both());
      expect(keys.isActive, isTrue);
      expect(keys.forClient('com.myweli.app')!.keyId, 'APPKEY0001');
      expect(keys.forClient('com.myweli.signin')!.keyId, 'APPKEY0001');
      expect(keys.forClient('com.myweli.pro')!.keyId, 'PROKEY0001');
      expect(keys.forClient('com.myweli.pro')!.teamId, 'TEAM123456');
      expect(keys.forClient('com.unknown.client'), isNull);
    });

    test('the key that signs is the slot\'s own .p8 — verified with its '
        'public half, refused by the other\'s', () {
      final keys = load(both());
      final appSecret = keys.forClient('com.myweli.app')!.clientSecret('x');
      final proSecret = keys.forClient('com.myweli.pro')!.clientSecret('x');
      expect(() => JWT.verify(appSecret, appPublic), returnsNormally);
      expect(() => JWT.verify(proSecret, proPublic), returnsNormally);
      expect(
        () => JWT.verify(proSecret, appPublic),
        throwsA(isA<JWTException>()),
      );
    });

    test('one slot only → active for its clients, the others uncovered', () {
      final m = both()
        ..remove('APPLE_PRO_KEY_ID')
        ..remove('APPLE_PRO_PRIVATE_KEY')
        ..remove('APPLE_PRO_KEY_CLIENTS');
      final keys = load(m);
      expect(keys.isActive, isTrue);
      expect(keys.forClient('com.myweli.pro'), isNull);
      expect(keys.uncovered(clients), ['com.myweli.pro']);
    });

    test('client lists are trimmed, empty entries ignored', () {
      final m = both()
        ..['APPLE_APP_KEY_CLIENTS'] = ' com.myweli.app , ,com.myweli.signin ';
      expect(load(m).forClient('com.myweli.signin'), isNotNull);
    });

    for (final slot in ['APP', 'PRO']) {
      for (final part in ['KEY_ID', 'PRIVATE_KEY', 'KEY_CLIENTS']) {
        test('rule 2: APPLE_${slot}_$part missing from a set slot → refused, '
            'naming it', () {
          final m = both()..remove('APPLE_${slot}_$part');
          expect(
            () => load(m),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('APPLE_${slot}_$part'),
              ),
            ),
          );
        });
      }
    }

    test('rule 3: a slot without APPLE_TEAM_ID → refused', () {
      final m = both()..remove('APPLE_TEAM_ID');
      expect(
        () => load(m),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('APPLE_TEAM_ID'),
          ),
        ),
      );
    });

    test('rule 4: a client that is not in APPLE_CLIENT_IDS → refused, '
        'naming the client (a typo would keep nothing, silently)', () {
      final m = both()..['APPLE_PRO_KEY_CLIENTS'] = 'com.myweli.prp';
      expect(
        () => load(m),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('com.myweli.prp'), contains('APPLE_CLIENT_IDS')),
          ),
        ),
      );
    });

    test('rule 4: one client in both slots → refused', () {
      final m = both()
        ..['APPLE_PRO_KEY_CLIENTS'] = 'com.myweli.pro,com.myweli.signin';
      expect(
        () => load(m),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('com.myweli.signin'),
          ),
        ),
      );
    });

    test('a slot listing no client → refused', () {
      final m = both()..['APPLE_PRO_KEY_CLIENTS'] = ' , ';
      expect(() => load(m), throwsStateError);
    });

    for (final old in ['APPLE_KEY_ID', 'APPLE_PRIVATE_KEY']) {
      test('rule 6: the old single-key name $old → refused, pointing at the '
          'new ones', () {
        expect(
          () => load({...both(), old: 'x'}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains(old), contains('APPLE_APP_KEY_ID')),
            ),
          ),
        );
        expect(() => load({old: 'x'}), throwsStateError);
      });
    }

    test('an unreadable .p8 → refused, naming the variable, never echoing '
        'the value', () {
      final m = both()..['APPLE_PRO_PRIVATE_KEY'] = 'not-a-key-SECRET';
      expect(
        () => load(m),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('APPLE_PRO_PRIVATE_KEY'), isNot(contains('SECRET'))),
          ),
        ),
      );
    });

    test('the .p8 with escaped newlines reads too', () {
      final m = both()
        ..['APPLE_APP_PRIVATE_KEY'] = appPem.replaceAll('\n', r'\n');
      final secret = load(m).forClient('com.myweli.app')!.clientSecret('x');
      expect(() => JWT.verify(secret, appPublic), returnsNormally);
    });
  });

  group('appleKeysNotice — what a production boot says', () {
    test('no key → the inactive NOTICE', () {
      expect(
        appleKeysNotice(AppleSignInKeys.none, clients),
        allOf(startsWith('NOTICE:'), contains('neither kept nor revoked')),
      );
    });

    test('a client without a key → a NOTICE naming it (rule 5)', () {
      final m = both()
        ..remove('APPLE_PRO_KEY_ID')
        ..remove('APPLE_PRO_PRIVATE_KEY')
        ..remove('APPLE_PRO_KEY_CLIENTS');
      final notice = appleKeysNotice(load(m), clients)!;
      expect(notice, startsWith('NOTICE:'));
      expect(notice, contains('com.myweli.pro'));
      expect(notice, isNot(contains('com.myweli.app,')));
    });

    test('every client covered → nothing to say', () {
      expect(appleKeysNotice(load(both()), clients), isNull);
    });
  });

  group('AppleTokenService — each token with its client\'s key', () {
    late InMemoryAppleTokenRepository repo;
    late List<http.Request> sent;
    late List<String> logs;

    setUp(() {
      repo = InMemoryAppleTokenRepository();
      sent = [];
      logs = [];
    });

    AppleTokenService service(
      AppleSignInKeys keys,
      Future<http.Response> Function(http.Request) answer,
    ) => AppleTokenService(
      repo,
      keys,
      client: MockClient((req) async {
        sent.add(req);
        return answer(req);
      }),
      log: logs.add,
    );

    String appleIdToken(String sub) => JWT({'sub': sub}).sign(SecretKey('x'));

    Future<http.Response> granted(http.Request _) async => http.Response(
      '{"refresh_token":"rt-1","id_token":"${appleIdToken('apple-sub')}"}',
      200,
    );

    Future<void> keep(AppleTokenService s, String clientId) => s.keepFromCode(
      kind: 'provider',
      accountId: 'acc',
      clientId: clientId,
      sub: 'apple-sub',
      code: 'code-1',
    );

    test('a Pro sign-in is exchanged with the Pro key, a MyWeli one with the '
        'MyWeli key', () async {
      final s = service(load(both()), granted);
      await keep(s, 'com.myweli.pro');
      await keep(s, 'com.myweli.app');
      expect(sent, hasLength(2));
      final pro = sent[0].bodyFields;
      final app = sent[1].bodyFields;
      expect(pro['client_id'], 'com.myweli.pro');
      expect(kidOf(pro['client_secret']!), 'PROKEY0001');
      expect(
        (JWT.verify(pro['client_secret']!, proPublic).payload as Map)['sub'],
        'com.myweli.pro',
      );
      expect(kidOf(app['client_secret']!), 'APPKEY0001');
      expect(
        (JWT.verify(app['client_secret']!, appPublic).payload as Map)['sub'],
        'com.myweli.app',
      );
    });

    test('a client with no key → no call, nothing kept, a SKIPPED line '
        'naming the client', () async {
      final m = both()
        ..remove('APPLE_PRO_KEY_ID')
        ..remove('APPLE_PRO_PRIVATE_KEY')
        ..remove('APPLE_PRO_KEY_CLIENTS');
      await keep(service(load(m), granted), 'com.myweli.pro');
      expect(sent, isEmpty);
      expect(await repo.listFor(kind: 'provider', accountId: 'acc'), isEmpty);
      expect(
        logs.single,
        allOf(
          contains('apple_token SKIPPED'),
          contains('no_key_for_client'),
          contains('com.myweli.pro'),
        ),
      );
    });

    test('deletion revokes each token with its own client\'s key; a token '
        'whose client has no key is skipped — and every row is still '
        'erased', () async {
      for (final c in clients) {
        await repo.keep(
          kind: 'provider',
          accountId: 'acc',
          clientId: c,
          refreshToken: 'rt-$c',
        );
      }
      final m = both()
        ..remove('APPLE_PRO_KEY_ID')
        ..remove('APPLE_PRO_PRIVATE_KEY')
        ..remove('APPLE_PRO_KEY_CLIENTS');
      await service(
        load(m),
        (_) async => http.Response('', 200),
      ).revokeAll(kind: 'provider', accountId: 'acc');

      final byClient = {for (final r in sent) r.bodyFields['client_id']: r};
      expect(
        byClient.keys,
        unorderedEquals(['com.myweli.app', 'com.myweli.signin']),
      );
      for (final r in sent) {
        expect(kidOf(r.bodyFields['client_secret']!), 'APPKEY0001');
      }
      expect(
        logs.where((l) => l.contains('apple_revoke SKIPPED')).single,
        allOf(contains('no_key_for_client'), contains('com.myweli.pro')),
      );
      expect(await repo.listFor(kind: 'provider', accountId: 'acc'), isEmpty);
    });

    test(
      'both keys → every token revoked, the Pro one with the Pro key',
      () async {
        for (final c in clients) {
          await repo.keep(
            kind: 'user',
            accountId: 'acc',
            clientId: c,
            refreshToken: 'rt-$c',
          );
        }
        await service(
          load(both()),
          (_) async => http.Response('', 200),
        ).revokeAll(kind: 'user', accountId: 'acc');
        final kids = {
          for (final r in sent)
            r.bodyFields['client_id']: kidOf(r.bodyFields['client_secret']!),
        };
        expect(kids, {
          'com.myweli.app': 'APPKEY0001',
          'com.myweli.signin': 'APPKEY0001',
          'com.myweli.pro': 'PROKEY0001',
        });
        expect(await repo.listFor(kind: 'user', accountId: 'acc'), isEmpty);
      },
    );
  });
}
