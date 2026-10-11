import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/refreshing_http_client.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/secure_session_store.dart';

Future<InMemorySessionStore> _store({String? refresh = 'r1'}) async {
  final s = InMemorySessionStore();
  await s.save(
    jsonEncode({
      'token': 'old-access',
      'refreshToken': refresh,
      'user': {'id': 'u1'},
    }),
  );
  return s;
}

RefreshingHttpClient _client(http.Client c, SessionStore store) =>
    RefreshingHttpClient(client: c, baseUrl: 'http://x', store: store);

Future<http.Response> _get(http.Client c, String token) => c.get(
  Uri.parse('http://x/me'),
  headers: {'Authorization': 'Bearer $token'},
);

void main() {
  test('a non-401 response passes straight through (no refresh)', () async {
    var calls = 0;
    final store = await _store();
    final mock = MockClient((req) async {
      calls++;
      return http.Response('ok', 200);
    });
    final res = await _client(mock, store).send((t) => _get(mock, t));

    expect(res!.statusCode, 200);
    expect(calls, 1); // no refresh round-trip
  });

  test(
    '401 → refresh → retry with the new token; session is rotated',
    () async {
      final store = await _store();
      final seen = <String?>[];
      final mock = MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          expect((jsonDecode(req.body) as Map)['refreshToken'], 'r1');
          return http.Response(
            jsonEncode({
              'accessToken': 'new-access',
              'refreshToken': 'r2',
              'expiresAt': DateTime.utc(2030).toIso8601String(),
            }),
            200,
          );
        }
        final auth =
            req.headers['authorization'] ?? req.headers['Authorization'];
        seen.add(auth);
        return http.Response('', auth == 'Bearer new-access' ? 200 : 401);
      });

      final res = await _client(mock, store).send((t) => _get(mock, t));

      expect(res!.statusCode, 200);
      expect(seen, ['Bearer old-access', 'Bearer new-access']); // retried once
      final stored = jsonDecode((await store.read())!) as Map<String, dynamic>;
      expect(stored['token'], 'new-access');
      expect(stored['refreshToken'], 'r2');
      expect(stored['user'], {'id': 'u1'}); // untouched
    },
  );

  test(
    'a rejected refresh (401) clears the session and surfaces the 401',
    () async {
      final store = await _store();
      final mock = MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          return http.Response(jsonEncode({'error': 'refresh_reused'}), 401);
        }
        return http.Response('', 401);
      });

      final res = await _client(mock, store).send((t) => _get(mock, t));

      expect(res!.statusCode, 401);
      expect(await store.read(), isNull); // session ended
    },
  );

  test(
    'a transport failure during refresh keeps the session (no logout)',
    () async {
      final store = await _store();
      final mock = MockClient((req) async {
        if (req.url.path == '/auth/refresh') throw Exception('network down');
        return http.Response('', 401);
      });

      final res = await _client(mock, store).send((t) => _get(mock, t));

      expect(res!.statusCode, 401);
      expect(await store.read(), isNotNull); // a flaky network must not log out
    },
  );

  test('a 401 with no stored refresh token clears the session', () async {
    final store = await _store(refresh: null);
    final mock = MockClient((req) async => http.Response('', 401));

    final res = await _client(mock, store).send((t) => _get(mock, t));

    expect(res!.statusCode, 401);
    expect(await store.read(), isNull);
  });

  test('with no session, send does nothing and returns null', () async {
    var calls = 0;
    final store = InMemorySessionStore();
    final mock = MockClient((req) async {
      calls++;
      return http.Response('', 200);
    });
    final client = _client(mock, store);

    expect(await client.send((t) => _get(mock, t)), isNull);
    expect(calls, 0);
    expect(await client.accessToken(), isNull);
  });

  group('one refresh at a time per session (session-refresh.md)', () {
    // A server that behaves like ours: refresh tokens are single-use, and a
    // reused one revokes the family (`refresh_reused`).
    MockClient singleUseServer({
      required List<String> refreshes,
      Completer<void>? holdRefresh,
    }) {
      final used = <String>{};
      return MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          final token = (jsonDecode(req.body) as Map)['refreshToken'] as String;
          refreshes.add(token);
          if (holdRefresh != null) await holdRefresh.future;
          if (!used.add(token)) {
            return http.Response(jsonEncode({'error': 'refresh_reused'}), 401);
          }
          return http.Response(
            jsonEncode({'accessToken': 'new-access', 'refreshToken': 'r2'}),
            200,
          );
        }
        final auth = req.headers['Authorization'];
        return http.Response('', auth == 'Bearer new-access' ? 200 : 401);
      });
    }

    test('two clients on one session, two concurrent 401s → ONE exchange, '
        'both retried, still signed in', () async {
      final store = await _store();
      final refreshes = <String>[];
      final hold = Completer<void>();
      final mock = singleUseServer(refreshes: refreshes, holdRefresh: hold);
      // Two services, each with its own client over the same session — the
      // cold-start shape (GET /me/provider + POST /me/devices).
      final a = _client(mock, store);
      final b = _client(mock, store);

      final both = Future.wait([
        a.send((t) => _get(mock, t)),
        b.send((t) => _get(mock, t)),
      ]);
      await pumpEventQueue();
      hold.complete();
      final res = await both;

      expect(refreshes, ['r1'], reason: 'the second 401 joins the first');
      expect(res.map((r) => r!.statusCode), [200, 200]);
      final stored = jsonDecode((await store.read())!) as Map<String, dynamic>;
      expect(stored['refreshToken'], 'r2', reason: 'never signed out');
    });

    test('equal store identities share the exchange (SecureSessionStore: '
        'the storage key)', () {
      expect(
        SecureSessionStore(key: 'k').identity,
        SecureSessionStore(key: 'k').identity,
      );
      expect(
        SecureSessionStore(key: 'k').identity,
        isNot(SecureSessionStore(key: 'other').identity),
      );
      expect(SecureSessionStore().identity, isNot(InMemorySessionStore()));
    });

    test('different sessions never share an exchange', () async {
      final refreshes = <String>[];
      final hold = Completer<void>();
      final mock = singleUseServer(refreshes: refreshes, holdRefresh: hold);
      final consumer = _client(mock, await _store(refresh: 'c1'));
      final provider = _client(mock, await _store(refresh: 'p1'));

      final both = Future.wait([
        consumer.send((t) => _get(mock, t)),
        provider.send((t) => _get(mock, t)),
      ]);
      await pumpEventQueue();
      hold.complete();
      await both;

      expect(refreshes..sort(), ['c1', 'p1']);
    });

    test('a 401 that lands after another request rotated the session retries '
        'with the stored token — no second exchange', () async {
      final store = await _store();
      final refreshes = <String>[];
      final seen = <String?>[];
      final mock = MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          refreshes.add('called');
          return http.Response('', 500);
        }
        final auth = req.headers['Authorization'];
        seen.add(auth);
        if (auth == 'Bearer old-access') {
          // Meanwhile another request finished its refresh.
          await store.save(
            jsonEncode({'token': 'new-access', 'refreshToken': 'r2'}),
          );
          return http.Response('', 401);
        }
        return http.Response('', 200);
      });

      final res = await _client(mock, store).send((t) => _get(mock, t));

      expect(res!.statusCode, 200);
      expect(seen, ['Bearer old-access', 'Bearer new-access']);
      expect(refreshes, isEmpty);
    });
  });

  test('mergeIntoSession updates fields while preserving the tokens', () async {
    final store = await _store();
    final client = _client(
      MockClient((_) async => http.Response('', 200)),
      store,
    );

    await client.mergeIntoSession({
      'user': {'id': 'u2'},
    });

    final stored = jsonDecode((await store.read())!) as Map<String, dynamic>;
    expect(stored['user'], {'id': 'u2'});
    expect(stored['token'], 'old-access');
    expect(stored['refreshToken'], 'r1');
  });
}
