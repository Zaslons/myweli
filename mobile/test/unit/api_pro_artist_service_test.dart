import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
ApiProArtistService _linked(MockClient client) {
  final store = InMemorySessionStore();
  store.save(jsonEncode({
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
      'providerId': 'provider1',
    },
  }));
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
          'total': 1
        }),
        200,
      );
    });
    final res = await _linked(client).getArtists('provider1');
    expect(res.success, isTrue);
    expect(res.data!.single.name, 'Awa');
  });

  test('createArtist POSTs; serializes workingHours; omits server fields',
      () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/providers/provider1/artists');
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_artistJson()), 201);
    });
    final res = await _linked(client).createArtist('provider1', {
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
  });

  test('updateArtist/deleteArtist resolve the salon from the session',
      () async {
    final calls = <String>[];
    MockClient client() => MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          return http.Response(jsonEncode(_artistJson()), 200);
        });
    expect(
      (await _linked(client()).updateArtist('artist1', {'name': 'A'})).success,
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
  });

  test('cross-salon error surfaces its code', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'error': 'forbidden'}), 403),
    );
    final res = await _linked(client).getArtists('provider1');
    expect(res.success, isFalse);
    expect(res.code, 'forbidden');
  });
}
