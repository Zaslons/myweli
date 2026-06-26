import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_providers_provider.dart';
import 'package:myweli/providers/admin/admin_users_provider.dart';
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

  group('AdminProvidersProvider', () {
    test('loads, suspend updates the row, feature flips featured', () async {
      final p = AdminProvidersProvider(
        service: svc(MockClient((req) async {
          if (req.url.path == '/admin/providers') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'p1',
                    'name': 'A',
                    'status': 'active',
                    'featured': false,
                    'rating': 4.5,
                  },
                ],
                'total': 1,
              }),
              200,
            );
          }
          if (req.url.path == '/admin/providers/p1/suspend') {
            return http.Response(
                jsonEncode({'id': 'p1', 'status': 'suspended'}), 200);
          }
          if (req.url.path == '/admin/providers/p1/feature') {
            return http.Response(
                jsonEncode({'id': 'p1', 'featured': true}), 200);
          }
          return http.Response('{}', 404);
        })),
      );

      await p.load();
      expect(p.items, hasLength(1));
      expect(await p.suspend('p1', 'abus'), isTrue);
      expect(p.items.single['status'], 'suspended');
      expect(await p.feature('p1', true), isTrue);
      expect(p.items.single['featured'], true);
    });

    test('under the Actifs filter, suspending drops the row', () async {
      final p = AdminProvidersProvider(
        service: svc(MockClient((req) async {
          if (req.url.path == '/admin/providers') {
            expect(req.url.queryParameters['status'], 'active');
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'p1', 'status': 'active'},
                ],
                'total': 1,
              }),
              200,
            );
          }
          return http.Response(
              jsonEncode({'id': 'p1', 'status': 'suspended'}), 200);
        })),
      );

      p.setFilter(1); // Actifs
      await p.load();
      expect(p.items, hasLength(1));
      expect(await p.suspend('p1', 'x'), isTrue);
      expect(p.items, isEmpty);
    });

    test('surfaces an action error and keeps the row', () async {
      final p = AdminProvidersProvider(
        service: svc(MockClient((req) async {
          if (req.url.path == '/admin/providers') {
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'p1', 'status': 'active'},
                ],
                'total': 1,
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'error': 'forbidden'}), 403);
        })),
      );
      await p.load();
      expect(await p.suspend('p1', 'x'), isFalse);
      expect(p.items, hasLength(1));
      expect(p.actionError, isNotNull);
    });
  });

  group('AdminUsersProvider', () {
    test('loads and bans; under Actifs the banned row drops', () async {
      final p = AdminUsersProvider(
        service: svc(MockClient((req) async {
          if (req.url.path == '/admin/users') {
            expect(req.url.queryParameters['status'], 'active');
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'u1', 'name': 'Awa', 'status': 'active'},
                ],
                'total': 1,
              }),
              200,
            );
          }
          return http.Response(
              jsonEncode({'id': 'u1', 'status': 'banned'}), 200);
        })),
      );

      p.setFilter(1); // Actifs
      await p.load();
      expect(p.items, hasLength(1));
      expect(await p.ban('u1', 'spam'), isTrue);
      expect(p.items, isEmpty);
    });

    test('search forwards the query', () async {
      var sawQuery = false;
      final p = AdminUsersProvider(
        service: svc(MockClient((req) async {
          if (req.url.queryParameters['q'] == 'awa') sawQuery = true;
          return http.Response(jsonEncode({'items': [], 'total': 0}), 200);
        })),
      );
      p.search('awa');
      await p.load();
      expect(sawQuery, isTrue);
    });
  });
}
