import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/services/api/api_pro_artist_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

Map<String, dynamic> _artistJson({String id = 'artist1'}) => {
  'id': id,
  'name': 'Awa',
  'imageUrl': null,
  'providerId': 'provider1',
  'specialization': 'Tresses',
  'rating': null,
  'reviewCount': null,
  'workingHours': <String, dynamic>{},
};

/// Provider-session-backed artist service linked to provider1.
ApiProArtistService _linked(MockClient client) => _withSession(client);

/// An artist service over a persisted provider session: the account's own
/// salon ([linked], null = a bare member account), the R6 [selected] salon,
/// and the cached membership's salon ([membershipSalon]).
ApiProArtistService _withSession(
  MockClient client, {
  String? linked = 'provider1',
  String? selected,
  String? membershipSalon,
}) {
  final store = InMemorySessionStore();
  store.save(
    jsonEncode({
      'token': 'tok',
      'refreshToken': 'r1',
      'provider': {
        'id': 'acc1',
        'phoneNumber': '+2250500000000',
        'businessName': 'Salon',
        'businessType': 'salon',
        'verificationStatus': 'pending',
        'kycDocs': <Map<String, dynamic>>[],
        'createdAt': '2026-01-01T00:00:00.000Z',
        'providerId': ?linked,
      },
      if (membershipSalon != null)
        'membership': {
          'role': 'manager',
          'capabilities': ['catalogue.manage'],
          'salonId': membershipSalon,
          'salonName': 'Beauté Divine',
        },
      'selectedSalonId': ?selected,
    }),
  );
  return ApiProArtistService(
    client: client,
    baseUrl: 'http://x',
    providerSessionStore: store,
  );
}

void main() {
  test('getArtists GETs /providers/{id}/artists → list', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/providers/provider1/artists');
      return http.Response(
        jsonEncode({
          'items': [_artistJson()],
          'total': 1,
        }),
        200,
      );
    });
    final res = await _linked(client).getArtists(SalonId('provider1'));
    expect(res.success, isTrue);
    expect(res.data!.single.name, 'Awa');
  });

  test('getArtists: an empty team the server sent is an empty list', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({'items': <Object>[], 'page': 1, 'total': 0}),
        200,
      ),
    );
    final res = await _linked(client).getArtists(SalonId('provider1'));
    expect(res.success, isTrue);
    expect(res.data, isEmpty);
  });

  // The server always sends `items`: a 200 without it is a body that did not
  // arrive whole, never « no team » — the salon export would ship it as
  // complete (docs/design/export-unreadable-200.md §2).
  group('getArtists: a 200 without its list is an error, not []', () {
    final bodies = <String, Map<String, Object?>>{
      '{}': {},
      'items: null': {'items': null, 'total': 0},
      'items: "x"': {'items': 'x', 'total': 0},
    };
    for (final MapEntry(key: name, value: body) in bodies.entries) {
      test(name, () async {
        final client = MockClient(
          (req) async => http.Response(jsonEncode(body), 200),
        );
        final res = await _linked(client).getArtists(SalonId('provider1'));
        expect(res.success, isFalse);
        expect(res.data, isNull);
      });
    }
  });

  test(
    'createArtist POSTs; serializes workingHours; omits server fields',
    () async {
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/providers/provider1/artists');
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_artistJson()), 201);
      });
      final res = await _linked(client).createArtist(SalonId('provider1'), {
        'name': 'Awa',
        'specialization': 'Tresses',
        'rating': 5, // must not be sent
        'workingHours': {
          1: [
            TimeSlot(
              startTime: DateTime.utc(2024, 1, 1, 9),
              endTime: DateTime.utc(2024, 1, 1, 17),
              isAvailable: true,
            ),
          ],
        },
      });
      expect(res.success, isTrue);
      expect(body!['name'], 'Awa');
      expect(body!.containsKey('rating'), isFalse); // server-owned
      // int weekday key → string; TimeSlot → json.
      expect((body!['workingHours'] as Map).containsKey('1'), isTrue);
    },
  );

  test(
    'updateArtist/deleteArtist resolve the salon from the session',
    () async {
      final calls = <String>[];
      MockClient client() => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response(jsonEncode(_artistJson()), 200);
      });
      expect(
        (await _linked(
          client(),
        ).updateArtist('artist1', {'name': 'A'})).success,
        isTrue,
      );
      final del = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response('', 204);
      });
      expect((await _linked(del).deleteArtist('artist1')).success, isTrue);
      expect(calls, [
        'PATCH /providers/provider1/artists/artist1',
        'DELETE /providers/provider1/artists/artist1',
      ]);
    },
  );

  // The artistId-only edits pick their salon from the session the same way
  // ProAuthProvider.activeSalonId does — selection → the account's own
  // salon → the membership's (docs/design/services-acting-salon.md).
  group('the artistId-only edits act in the session\'s acting salon', () {
    Future<List<String>> editAndDelete(
      ApiProArtistService Function(MockClient) build,
    ) async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return req.method == 'DELETE'
            ? http.Response('', 204)
            : http.Response(jsonEncode(_artistJson()), 200);
      });
      final service = build(client);
      final updated = await service.updateArtist('artist1', {'name': 'A'});
      expect(updated.success, isTrue, reason: updated.error);
      final deleted = await service.deleteArtist('artist1');
      expect(deleted.success, isTrue, reason: deleted.error);
      return calls;
    }

    test('an owner switched to their second salon edits THAT salon\'s '
        'staff, not the default salon\'s', () async {
      final calls = await editAndDelete(
        (c) => _withSession(c, linked: 'provider1', selected: 'provider2'),
      );
      expect(calls, [
        'PATCH /providers/provider2/artists/artist1',
        'DELETE /providers/provider2/artists/artist1',
      ]);
    });

    test('a bare member account (no salon of its own) acts in its '
        'membership\'s salon instead of being refused client-side', () async {
      final calls = await editAndDelete(
        (c) => _withSession(c, linked: null, membershipSalon: 'provider2'),
      );
      expect(calls, [
        'PATCH /providers/provider2/artists/artist1',
        'DELETE /providers/provider2/artists/artist1',
      ]);
    });

    test(
      'no salon anywhere in the session → refused before any request',
      () async {
        final client = MockClient(
          (req) async => throw StateError('no request should go out'),
        );
        final service = _withSession(client, linked: null);
        final updated = await service.updateArtist('artist1', {'name': 'A'});
        expect(updated.success, isFalse);
        expect(updated.error, 'Compte non lié à un salon');
        expect((await service.deleteArtist('artist1')).success, isFalse);
      },
    );
  });

  test('cross-salon error surfaces its code', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'error': 'forbidden'}), 403),
    );
    final res = await _linked(client).getArtists(SalonId('provider1'));
    expect(res.success, isFalse);
    expect(res.code, 'forbidden');
  });
}
