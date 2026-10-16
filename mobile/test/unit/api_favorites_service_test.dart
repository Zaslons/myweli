import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_favorites_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// A salon as `GET /me/favorites` hydrates it (the fields the parse needs).
Map<String, dynamic> _salonJson(String id) => {
  'id': id,
  'name': 'Salon $id',
  'description': 'desc',
  'address': 'addr',
  'imageUrls': <String>[],
  'rating': 4.5,
  'reviewCount': 1,
  'services': <Map<String, dynamic>>[],
  'availability': {
    'providerId': id,
    'weeklySchedule': <String, dynamic>{},
    'blockedDates': <String>[],
  },
  'phoneNumber': '+22500',
  'category': 'salon',
};

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
          'providerIds': ['p1', 'p2'],
        }),
        200,
      );
    });
    final res = await _service(client).getFavoriteProviderIds('u1');
    expect(res.success, isTrue);
    expect(res.data, ['p1', 'p2']);
  });

  group('getFavoriteProviders', () {
    /// A favorites service whose `GET /me/favorites` answers [body] with a 200.
    ApiFavoritesService answering(Object body) => _service(
      MockClient((req) async {
        expect(req.url.path, '/me/favorites');
        return http.Response(jsonEncode(body), 200);
      }),
    );

    test('CONTROL: the hydrated salons the server sent', () async {
      final res = await answering({
        'providerIds': ['p1'],
        'providers': [_salonJson('p1')],
      }).getFavoriteProviders('u1');
      expect(res.success, isTrue);
      expect(res.data!.single.name, 'Salon p1');
    });

    // FavoritesService.list drops a favourite whose salon no longer EXISTS
    // (spec §5): `providerIds` then runs longer than `providers`. That is a
    // real answer — a guard that compared the two would refuse it for ever,
    // here and in « Mes données ».
    test('CONTROL: a favourite whose salon is gone — more ids than salons, '
        'still the salons the server sent', () async {
      final res = await answering({
        'providerIds': ['p1', 'gone'],
        'providers': [_salonJson('p1')],
      }).getFavoriteProviders('u1');
      expect(res.success, isTrue);
      expect(res.data!.single.id, 'p1');
    });

    test('CONTROL: an empty list the server sent is no favourites', () async {
      final res = await answering({
        'providerIds': <String>[],
        'providers': <Object>[],
      }).getFavoriteProviders('u1');
      expect(res.success, isTrue);
      expect(res.data, isEmpty);
    });

    // The server always sends `providers`: a 200 without it is a body that
    // did not arrive whole, never « no favourites » — « Mes données » would
    // copy it as complete (docs/design/export-unreadable-200.md §2).
    final withoutTheList = <String, Map<String, Object?>>{
      '{}': {},
      'providers: null': {'providers': null},
      'providers: "x"': {'providers': 'x'},
      'the ids without the salons': {
        'providerIds': ['p1'],
      },
    };
    for (final MapEntry(key: name, value: body) in withoutTheList.entries) {
      test('a 200 without its list ($name) is an error, not []', () async {
        final res = await answering(body).getFavoriteProviders('u1');
        expect(res.success, isFalse);
        expect(res.data, isNull);
      });
    }
  });

  test(
    'addFavorite POSTs, removeFavorite DELETEs the providerId path',
    () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response('', 204);
      });
      expect((await _service(client).addFavorite('u1', 'p1')).success, isTrue);
      expect(
        (await _service(client).removeFavorite('u1', 'p1')).success,
        isTrue,
      );
      expect(calls, ['POST /me/favorites/p1', 'DELETE /me/favorites/p1']);
    },
  );

  test('isFavorite is derived from the list (one GET)', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/me/favorites');
      return http.Response(
        jsonEncode({
          'providerIds': ['p1'],
        }),
        200,
      );
    });
    expect((await _service(client).isFavorite('u1', 'p1')).data, isTrue);
    expect((await _service(client).isFavorite('u1', 'p2')).data, isFalse);
  });

  test('no session → fails fast without HTTP', () async {
    final client = MockClient(
      (req) async => throw Exception('should not be called'),
    );
    final res = await _service(
      client,
      token: null,
    ).getFavoriteProviderIds('u1');
    expect(res.success, isFalse);
  });

  test(
    'a 401 triggers consumer silent refresh (/auth/refresh) + retry',
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
    },
  );
}
