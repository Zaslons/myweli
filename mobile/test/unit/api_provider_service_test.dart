import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_provider_service.dart';

Map<String, dynamic> _providerJson(
  String id, {
  String category = 'salon',
  double rating = 4.5,
}) {
  return {
    'id': id,
    'name': 'Salon $id',
    'description': 'desc',
    'address': 'addr',
    'imageUrls': <String>[],
    'rating': rating,
    'reviewCount': 1,
    'services': <Map<String, dynamic>>[],
    'availability': {
      'providerId': id,
      'weeklySchedule': <String, dynamic>{},
      'blockedDates': <String>[],
    },
    'phoneNumber': '+22500',
    'category': category,
  };
}

void main() {
  test(
    'getProviders parses items from the paged envelope + sends filters',
    () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/providers');
        expect(req.url.queryParameters['category'], 'salon');
        expect(req.url.queryParameters['pageSize'], '20');
        return http.Response(
          jsonEncode({
            'items': [_providerJson('p1'), _providerJson('p2')],
            'page': 1,
            'pageSize': 20,
            'total': 2,
          }),
          200,
        );
      });
      final service = ApiProviderService(client: client, baseUrl: 'http://x');

      final res = await service.getProviders(category: 'salon');

      expect(res.success, isTrue);
      expect(res.data!.map((p) => p.id), ['p1', 'p2']);
    },
  );

  test('getProviderById returns the provider on 200', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode(_providerJson('p1')), 200),
    );
    final service = ApiProviderService(client: client, baseUrl: 'http://x');

    final res = await service.getProviderById('p1');

    expect(res.success, isTrue);
    expect(res.data!.id, 'p1');
  });

  test('getProviderById surfaces a 404 as an error, WITH a code', () async {
    // The code is the point. This service was the only one that never set
    // `code:`, so a screen could tell « this salon is gone » from « your
    // connection dropped » only by comparing French sentences — and the
    // sentence it compared against was « Provider non trouvé », English
    // jargon on a consumer screen. Those two failures need opposite
    // treatments under §12: the first has no retry that can succeed, the
    // second is exactly where « Réessayer » belongs.
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'error': 'not_found'}), 404),
    );
    final service = ApiProviderService(client: client, baseUrl: 'http://x');

    final res = await service.getProviderById('nope');

    expect(res.success, isFalse);
    expect(res.code, 'not_found');
    expect(res.error, isNot(contains('Provider')));
  });

  test('a transport failure carries a DIFFERENT code', () async {
    // The pair. Without it, a service that stamped `code: 'not_found'` on
    // every failure would pass the test above and collapse the distinction it
    // exists to create.
    final client = MockClient((req) async => throw Exception('down'));
    final service = ApiProviderService(client: client, baseUrl: 'http://x');

    final res = await service.getProviderById('p1');

    expect(res.success, isFalse);
    expect(res.code, 'network');
  });

  test('a transport failure becomes a friendly error', () async {
    final client = MockClient((req) async => throw Exception('down'));
    final service = ApiProviderService(client: client, baseUrl: 'http://x');

    final res = await service.getProviders();

    expect(res.success, isFalse);
    expect(res.error, isNotNull);
  });

  test('getFeaturedProviders requests a small page', () async {
    String? size;
    final client = MockClient((req) async {
      size = req.url.queryParameters['pageSize'];
      return http.Response(
        jsonEncode({'items': [], 'page': 1, 'pageSize': 3, 'total': 0}),
        200,
      );
    });
    final service = ApiProviderService(client: client, baseUrl: 'http://x');

    await service.getFeaturedProviders();

    expect(size, '3');
  });
}
