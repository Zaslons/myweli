import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/refreshing_http_client.dart';
import 'package:myweli/services/interfaces/session_store.dart';

Future<InMemorySessionStore> _store({String? refresh = 'r1'}) async {
  final s = InMemorySessionStore();
  await s.save(jsonEncode({
    'token': 'old-access',
    'refreshToken': refresh,
    'user': {'id': 'u1'},
  }));
  return s;
}

RefreshingHttpClient _client(http.Client c, SessionStore store) =>
    RefreshingHttpClient(client: c, baseUrl: 'http://x', store: store);

Future<http.Response> _get(http.Client c, String token) => c
    .get(Uri.parse('http://x/me'), headers: {'Authorization': 'Bearer $token'});

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

  test('401 → refresh → retry with the new token; session is rotated',
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
      final auth = req.headers['authorization'] ?? req.headers['Authorization'];
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
  });

  test('a rejected refresh (401) clears the session and surfaces the 401',
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
  });

  test('a transport failure during refresh keeps the session (no logout)',
      () async {
    final store = await _store();
    final mock = MockClient((req) async {
      if (req.url.path == '/auth/refresh') throw Exception('network down');
      return http.Response('', 401);
    });

    final res = await _client(mock, store).send((t) => _get(mock, t));

    expect(res!.statusCode, 401);
    expect(await store.read(), isNotNull); // a flaky network must not log out
  });

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

  test('mergeIntoSession updates fields while preserving the tokens', () async {
    final store = await _store();
    final client =
        _client(MockClient((_) async => http.Response('', 200)), store);

    await client.mergeIntoSession({
      'user': {'id': 'u2'}
    });

    final stored = jsonDecode((await store.read())!) as Map<String, dynamic>;
    expect(stored['user'], {'id': 'u2'});
    expect(stored['token'], 'old-access');
    expect(stored['refreshToken'], 'r1');
  });
}
