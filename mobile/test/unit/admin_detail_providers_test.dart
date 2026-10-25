import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_provider_detail_provider.dart';
import 'package:myweli/providers/admin/admin_user_detail_provider.dart';
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

  test(
    'provider detail splits entity + bookings; suspend updates status',
    () async {
      final p = AdminProviderDetailProvider(
        service: svc(
          MockClient((req) async {
            if (req.method == 'GET' && req.url.path == '/admin/providers/p1') {
              return http.Response(
                jsonEncode({
                  'id': 'p1',
                  'name': 'Beauté Divine',
                  'status': 'active',
                  'featured': true,
                  'recentAppointments': [
                    {'id': 'a1', 'status': 'completed', 'totalPrice': 15000},
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({'id': 'p1', 'status': 'suspended'}),
              200,
            );
          }),
        ),
      );

      await p.load('p1');
      expect(p.provider?['name'], 'Beauté Divine');
      expect(p.provider!.containsKey('recentAppointments'), isFalse);
      expect(p.appointments, hasLength(1));

      expect(await p.suspend('p1', 'abus'), isTrue);
      expect(p.provider?['status'], 'suspended');
      // The featured flag from the original load is preserved across the merge.
      expect(p.provider?['featured'], true);
    },
  );

  test('user detail loads; ban updates status', () async {
    final p = AdminUserDetailProvider(
      service: svc(
        MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/admin/users/u1') {
            return http.Response(
              jsonEncode({
                'id': 'u1',
                'name': 'Awa',
                'status': 'active',
                'recentAppointments': [],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'id': 'u1', 'status': 'banned'}),
            200,
          );
        }),
      ),
    );

    await p.load('u1');
    expect(p.user?['name'], 'Awa');
    expect(p.appointments, isEmpty);
    expect(await p.ban('u1', 'spam'), isTrue);
    expect(p.user?['status'], 'banned');
  });

  test('detail load surfaces an error', () async {
    final p = AdminProviderDetailProvider(
      service: svc(
        MockClient(
          (req) async => http.Response(jsonEncode({'error': 'not_found'}), 404),
        ),
      ),
    );
    await p.load('nope');
    expect(p.provider, isNull);
    expect(p.error, isNotNull);
  });

  // docs/design/hygiene-batch9.md §14 (B9.8): the provider is app-wide and
  // outlives the screen. The way to salon B showed salon A — its name, its
  // status, and « Suspendre » acting on B's id — until B answered; when B's
  // read failed, A stayed, with no error at all.
  test('the way to B drops A; a late answer for A is nobody\'s', () async {
    final a = Completer<http.Response>();
    final b = Completer<http.Response>();
    var firstA = true;
    final p = AdminProviderDetailProvider(
      service: svc(
        MockClient((req) {
          if (req.url.path == '/admin/providers/a') {
            if (firstA) {
              firstA = false;
              return Future.value(
                http.Response(jsonEncode({'id': 'a', 'name': 'Salon A'}), 200),
              );
            }
            return a.future;
          }
          return b.future;
        }),
      ),
    );

    await p.load('a');
    expect(p.provider?['name'], 'Salon A');

    unawaited(p.load('a'));
    unawaited(p.load('b'));
    expect(p.id, 'b');
    expect(p.provider, isNull, reason: 'A, on B\'s screen');

    a.complete(http.Response(jsonEncode({'id': 'a', 'name': 'Salon A'}), 200));
    await pumpEventQueue();
    expect(p.provider, isNull, reason: 'A\'s late answer, written under B');

    b.complete(http.Response('{}', 503));
    await pumpEventQueue();
    expect(p.provider, isNull);
    expect(p.error, isNotNull, reason: 'a failed B is an error, not A');
  });
}
