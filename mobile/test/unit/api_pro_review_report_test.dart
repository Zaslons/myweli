import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_pro_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// docs/design/backend-integrity-batch6.md §2.6 (B6.6): the salon's report
/// goes to the session-scoped route, with its reason — and says when nothing
/// answered or the server refused.
void main() {
  Future<InMemorySessionStore> pro() async {
    final store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
    return store;
  }

  test('POST /me/provider/reviews/{id}/report with the reason', () async {
    late http.Request sent;
    final svc = ApiProService(
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'status': 'reported'}), 200);
      }),
      baseUrl: 'http://x',
      providerSessionStore: await pro(),
    );
    final r = await svc.reportSalonReview('r/1', reason: 'Insultes');
    expect(r.success, isTrue);
    expect(sent.method, 'POST');
    expect(sent.url.path, '/me/provider/reviews/r%2F1/report');
    expect(jsonDecode(sent.body), {'reason': 'Insultes'});
  });

  test('no reason: an empty body — a report all the same', () async {
    late http.Request sent;
    final svc = ApiProService(
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'status': 'reported'}), 200);
      }),
      baseUrl: 'http://x',
      providerSessionStore: await pro(),
    );
    expect((await svc.reportSalonReview('r1', reason: '  ')).success, isTrue);
    expect(jsonDecode(sent.body), <String, dynamic>{});
  });

  test('a refusal (403) and no answer are failures', () async {
    final refused = ApiProService(
      client: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'forbidden'}), 403),
      ),
      baseUrl: 'http://x',
      providerSessionStore: await pro(),
    );
    expect((await refused.reportSalonReview('r1')).success, isFalse);

    final silent = ApiProService(
      client: MockClient((_) async => throw http.ClientException('reset')),
      baseUrl: 'http://x',
      providerSessionStore: await pro(),
    );
    final r = await silent.reportSalonReview('r1');
    expect(r.success, isFalse);
    expect(r.error, 'Pas de connexion. Réessayez.');
  });

  test('the selected salon crosses as ?salonId= — the report is that '
      'salon’s', () async {
    final store = InMemorySessionStore();
    await store.save(
      jsonEncode({
        'token': 't',
        'refreshToken': 'r',
        // A real session: `ProviderSession.fromJson` needs its account.
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
        'selectedSalonId': 'provider2',
      }),
    );
    late http.Request sent;
    final svc = ApiProService(
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'status': 'reported'}), 200);
      }),
      baseUrl: 'http://x',
      providerSessionStore: store,
    );
    expect((await svc.reportSalonReview('r1')).success, isTrue);
    expect(sent.url.queryParameters['salonId'], 'provider2');
  });
}
