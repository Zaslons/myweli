import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_favorites_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// A favorites service backed by a (consumer) session.
ApiFavoritesService _service(MockClient client, {String? token = 'tok'}) {
  final store = InMemorySessionStore();
  if (token != null) {
    store.save(jsonEncode({'token': token, 'refreshToken': 'r1'}));
  }
  return ApiFavoritesService(
    client: client,
    baseUrl: 'http://x',
    sessionStore: store,
  );
}

void main() {
  test('getFavoriteProviderIds GETs /me/favorites → ids', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/me/favorites');
      expect(req.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode({
          'providerIds': ['p1', 'p2']
        }),
        200,
      );
    });
    final res = await _service(client).getFavoriteProviderIds('u1');
    expect(res.success, isTrue);
    expect(res.data, ['p1', 'p2']);
  });

  test('addFavorite POSTs, removeFavorite DELETEs the providerId path',
      () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      return http.Response('', 204);
    });
    expect((await _service(client).addFavorite('u1', 'p1')).success, isTrue);
    expect((await _service(client).removeFavorite('u1', 'p1')).success, isTrue);
    expect(calls, [
      'POST /me/favorites/p1',
      'DELETE /me/favorites/p1',
    ]);
  });

  test('isFavorite is derived from the list (one GET)', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/me/favorites');
      return http.Response(
          jsonEncode({
            'providerIds': ['p1']
          }),
          200);
    });
    expect((await _service(client).isFavorite('u1', 'p1')).data, isTrue);
    expect((await _service(client).isFavorite('u1', 'p2')).data, isFalse);
  });

  test('no session → fails fast without HTTP', () async {
    final client =
        MockClient((req) async => throw Exception('should not be called'));
    final res =
        await _service(client, token: null).getFavoriteProviderIds('u1');
    expect(res.success, isFalse);
  });

  test('a 401 triggers consumer silent refresh (/auth/refresh) + retry',
      () async {
    var refreshed = false;
    final client = MockClient((req) async {
      if (req.url.path == '/auth/refresh') {
        refreshed = true;
        return http.Response(
          jsonEncode({
            'accessToken': 'tok2',
            'refreshToken': 'r2',
            'expiresAt': DateTime(2030).toIso8601String(),
          }),
          200,
        );
      }
      final auth = req.headers['Authorization'];
      if (auth != 'Bearer tok2') {
        return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
      }
      return http.Response(jsonEncode({'providerIds': <String>[]}), 200);
    });
    final res = await _service(client).getFavoriteProviderIds('u1');
    expect(res.success, isTrue);
    expect(refreshed, isTrue);
  });
}
