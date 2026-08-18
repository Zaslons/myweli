import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_client_version_provider.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// The admin side of the version floors (docs/design/client-version-gate.md §14).
void main() {
  late InMemorySessionStore store;

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  AdminService svc(MockClient c) =>
      AdminService(client: c, baseUrl: 'http://x', store: store);

  Map<String, dynamic> row({
    String app = 'com.myweli.app',
    String platform = 'android',
    int min = 0,
    int rec = 0,
    String? url = 'https://play/x',
  }) => {
    'appId': app,
    'platform': platform,
    'minimumBuild': min,
    'recommendedBuild': rec,
    'updateUrl': url,
  };

  test('loads the four rows', () async {
    final p = AdminClientVersionProvider(
      service: svc(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'items': [
                row(),
                row(platform: 'ios', url: null),
                row(app: 'com.myweli.pro'),
                row(app: 'com.myweli.pro', platform: 'ios', url: null),
              ],
            }),
            200,
          ),
        ),
      ),
    );
    await p.load();
    expect(p.floors, hasLength(4));
    expect(p.error, isNull);
    // iOS ships with no store URL — the nullability is the design, and the
    // screen renders it as « manquant » rather than pretending otherwise.
    expect(p.floors[1]['updateUrl'], isNull);
  });

  test(
    'PUTs to the right path with the right body, and patches in place',
    () async {
      Map<String, dynamic>? sent;
      final p = AdminClientVersionProvider(
        service: svc(
          MockClient((req) async {
            if (req.method == 'GET') {
              return http.Response(
                jsonEncode({
                  'items': [row()],
                }),
                200,
              );
            }
            expect(req.method, 'PUT');
            expect(req.url.path, '/admin/client-version');
            sent = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode(row(min: 12, rec: 14)), 200);
          }),
        ),
      );
      await p.load();
      final ok = await p.setFloor(
        appId: 'com.myweli.app',
        platform: 'android',
        minimumBuild: 12,
        recommendedBuild: 14,
        updateUrl: 'https://play/x',
      );

      expect(ok, isTrue);
      expect(sent!['minimumBuild'], 12);
      expect(sent!['recommendedBuild'], 14);
      // Patched from the server's response rather than re-fetched: the row we
      // just saved is the row it returned.
      expect(p.floors.single['minimumBuild'], 12);
    },
  );

  test('a null updateUrl is sent as null, not omitted or ""', () async {
    // The backend treats null as "no store listing yet", which is what makes it
    // refuse to block iOS. An empty string would be a URL that opens nothing.
    Map<String, dynamic>? sent;
    final p = AdminClientVersionProvider(
      service: svc(
        MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(row(url: null)), 200);
        }),
      ),
    );
    await p.setFloor(
      appId: 'com.myweli.app',
      platform: 'ios',
      minimumBuild: 3,
      recommendedBuild: 0,
      updateUrl: null,
    );
    expect(sent!.containsKey('updateUrl'), isTrue);
    expect(sent!['updateUrl'], isNull);
  });

  test(
    'a failed save exposes the CODE, so the screen can find the field',
    () async {
      // The screen routes a field-shaped fault to its field rather than a
      // snackbar (SYSTEM.md §830). It can only do that if the code survives the
      // service layer.
      final p = AdminClientVersionProvider(
        service: svc(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'error': 'recommended_below_minimum'}),
              400,
            ),
          ),
        ),
      );
      final ok = await p.setFloor(
        appId: 'com.myweli.app',
        platform: 'android',
        minimumBuild: 10,
        recommendedBuild: 5,
        updateUrl: null,
      );
      expect(ok, isFalse);
      expect(p.actionCode, 'recommended_below_minimum');
      // And the human sentence is French and actionable, not the raw code.
      expect(p.actionError, contains('recommandé'));
      expect(p.actionError, isNot(contains('_')));
    },
  );

  test('a load failure surfaces as an error, not an empty table', () async {
    final p = AdminClientVersionProvider(
      service: svc(MockClient((_) async => http.Response('{}', 500))),
    );
    await p.load();
    expect(p.error, isNotNull);
    expect(p.floors, isEmpty);
  });
}
