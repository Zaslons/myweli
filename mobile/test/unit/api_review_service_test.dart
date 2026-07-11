import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/services/api/api_review_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

Review _review({String appointmentId = 'appt1'}) => Review(
      id: 'r1',
      appointmentId: appointmentId,
      providerId: 'provider1',
      userId: 'u1',
      userName: 'Awa',
      rating: 5,
      text: 'Super',
      createdAt: DateTime.utc(2030),
    );

Map<String, dynamic> _reviewJson() => {
      'id': 'rev1',
      'appointmentId': 'appt1',
      'providerId': 'provider1',
      'userId': 'u1',
      'userName': 'Awa',
      'rating': 5,
      'text': 'Super',
      'verified': true,
      'artistId': 'artist1',
      'artistName': 'Awa',
      'serviceName': 'Coupe',
      'photoUrls': <String>[],
      'createdAt': DateTime.utc(2030).toIso8601String(),
    };

ApiReviewService _service(MockClient client, {String? token = 'tok'}) {
  final store = InMemorySessionStore();
  if (token != null) {
    store.save(jsonEncode({'token': token, 'refreshToken': 'r1'}));
  }
  return ApiReviewService(
    client: client,
    baseUrl: 'http://x',
    sessionStore: store,
  );
}

void main() {
  test('submitReview POSTs /appointments/{id}/review with rating/text/photos',
      () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/appointments/appt1/review');
      expect(req.headers['Authorization'], 'Bearer tok');
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_reviewJson()), 201);
    });
    final res = await _service(client).submitReview(_review());
    expect(res.success, isTrue);
    expect(res.data!.verified, isTrue);
    expect(res.data!.serviceName, 'Coupe');
    expect(body!['rating'], 5);
    expect(body!.containsKey('providerId'), isFalse); // server derives it
  });

  test('submitReview without an appointmentId fails fast', () async {
    final client =
        MockClient((req) async => throw Exception('should not be called'));
    final res = await _service(client).submitReview(_review(appointmentId: ''));
    expect(res.success, isFalse);
  });

  test('submitReview surfaces not_completed', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'error': 'not_completed'}), 403),
    );
    final res = await _service(client).submitReview(_review());
    expect(res.success, isFalse);
    expect(res.code, 'not_completed');
  });

  test('getProviderReviews GETs the public paginated list (no auth needed)',
      () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/providers/provider1/reviews');
      expect(req.url.queryParameters['page'], '2');
      return http.Response(
        jsonEncode({
          'items': [_reviewJson()],
          'total': 1,
          'page': 2,
          'pageSize': 20
        }),
        200,
      );
    });
    final res = await _service(client, token: null)
        .getProviderReviews('provider1', page: 2);
    expect(res.success, isTrue);
    expect(res.data!.single.serviceName, 'Coupe');
  });

  test('reportReview POSTs /reviews/{id}/report with the trimmed reason',
      () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response('{}', 200);
    });
    final res = await _service(client).reportReview('rev9', reason: '  spam  ');
    expect(res.success, isTrue);
    expect(captured.url.path, '/reviews/rev9/report');
    expect(jsonDecode(captured.body), {'reason': 'spam'});
  });

  test('reportReview without a session fails fast in French', () async {
    final client = MockClient((req) async => http.Response('{}', 200));
    final res = await _service(client, token: null).reportReview('rev9');
    expect(res.success, isFalse);
    expect(res.error, contains('Connectez-vous'));
  });
}
