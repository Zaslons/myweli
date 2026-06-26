import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_audit_provider.dart';
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

  test('loads entries + total; hasNext when more pages exist', () async {
    final p = AdminAuditProvider(
      service: svc(MockClient((req) async {
        return http.Response(
          jsonEncode({
            'items': [
              {'id': 'a1', 'action': 'kyc.approve', 'actorAdminId': 'adm'},
            ],
            'page': 1,
            'pageSize': 50,
            'total': 120,
          }),
          200,
        );
      })),
    );

    await p.load();
    expect(p.items, hasLength(1));
    expect(p.total, 120);
    expect(p.hasPrev, isFalse);
    expect(p.hasNext, isTrue); // 1*50 < 120
  });

  test('setAction resets to page 1 and forwards the action filter', () async {
    final pages = <String?>[];
    final actions = <String?>[];
    final p = AdminAuditProvider(
      service: svc(MockClient((req) async {
        pages.add(req.url.queryParameters['page']);
        actions.add(req.url.queryParameters['action']);
        return http.Response(
          jsonEncode({'items': [], 'total': 0}),
          200,
        );
      })),
    );

    await p.load();
    p.nextPage(); // no-op: total 0 → hasNext false
    p.setAction('review.hide');
    await p.load();
    expect(actions.last, 'review.hide');
    expect(pages.last, '1');
  });

  test('next/prev page navigation moves the window', () async {
    final p = AdminAuditProvider(
      service: svc(MockClient((req) async {
        return http.Response(
          jsonEncode({'items': [], 'total': 200}),
          200,
        );
      })),
    );
    await p.load();
    expect(p.page, 1);
    p.nextPage();
    await p.load();
    expect(p.page, 2);
    expect(p.hasPrev, isTrue);
    p.prevPage();
    await p.load();
    expect(p.page, 1);
  });
}
