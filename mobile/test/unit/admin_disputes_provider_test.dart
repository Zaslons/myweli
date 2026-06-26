import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_dispute_detail_provider.dart';
import 'package:myweli/providers/admin/admin_disputes_provider.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

void main() {
  late InMemorySessionStore store;

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  AdminService svc(MockClient c) =>
      AdminService(client: c, baseUrl: 'http://x', store: store);

  test('disputes list defaults to open; filter forwards status', () async {
    String? lastStatus;
    final p = AdminDisputesProvider(
      service: svc(MockClient((req) async {
        lastStatus = req.url.queryParameters['status'];
        return http.Response(
          jsonEncode({
            'items': [
              {'id': 'd1', 'reason': 'x', 'status': 'open'},
            ],
            'total': 1,
          }),
          200,
        );
      })),
    );

    await p.load();
    expect(lastStatus, 'open'); // default filter = Ouverts
    expect(p.items, hasLength(1));

    p.setFilter(2); // Tous → no status param
    await p.load();
    expect(lastStatus, isNull);
  });

  test('open posts the dispute', () async {
    var posted = false;
    final p = AdminDisputesProvider(
      service: svc(MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/admin/disputes') {
          posted = true;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['appointmentId'], 'a1');
          return http.Response(jsonEncode({'id': 'd1'}), 200);
        }
        return http.Response('{}', 404);
      })),
    );
    expect(await p.open('a1', 'litige'), isTrue);
    expect(posted, isTrue);
  });

  test('detail splits dispute/appointment/evidence; resolve updates status',
      () async {
    final p = AdminDisputeDetailProvider(
      service: svc(MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/admin/disputes/d1') {
          return http.Response(
            jsonEncode({
              'dispute': {'id': 'd1', 'status': 'open', 'reason': 'x'},
              'appointment': {
                'id': 'a1',
                'status': 'confirmed',
                'totalPrice': 9000
              },
              'depositScreenshotUrl': 'https://signed/x.jpg',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'id': 'd1', 'status': 'resolved', 'resolution': 'ok'}),
          200,
        );
      })),
    );

    await p.load('d1');
    expect(p.dispute?['reason'], 'x');
    expect(p.appointment?['id'], 'a1');
    expect(p.evidenceUrl, 'https://signed/x.jpg');

    expect(await p.resolve('d1', 'remboursé'), isTrue);
    expect(p.dispute?['status'], 'resolved');
  });
}
