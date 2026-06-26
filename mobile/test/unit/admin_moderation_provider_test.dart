import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_moderation_provider.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

void main() {
  late InMemorySessionStore store;

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  AdminModerationProvider provider(MockClient client) =>
      AdminModerationProvider(
        service:
            AdminService(client: client, baseUrl: 'http://x', store: store),
      );

  test('loadReported populates; hide removes the row optimistically', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path == '/admin/reviews/reports') {
        return http.Response(
          jsonEncode({
            'items': [
              {'reviewId': 'r1', 'rating': 1, 'text': 'x', 'reportCount': 2},
            ],
            'total': 1,
          }),
          200,
        );
      }
      if (req.url.path == '/admin/reviews/r1/hide') {
        return http.Response(jsonEncode({'moderationStatus': 'hidden'}), 200);
      }
      return http.Response('{}', 404);
    }));

    await p.loadReported();
    expect(p.reported, hasLength(1));
    expect(await p.hide('r1', 'abusif'), isTrue);
    expect(p.reported, isEmpty);
  });

  test('dismiss removes the reported row', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path == '/admin/reviews/reports') {
        return http.Response(
          jsonEncode({
            'items': [
              {'reviewId': 'r1', 'rating': 3, 'text': 'x', 'reportCount': 1},
            ],
            'total': 1,
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'dismissed'}), 200);
    }));
    await p.loadReported();
    expect(await p.dismiss('r1'), isTrue);
    expect(p.reported, isEmpty);
  });

  test('loadHidden populates; restore removes the row', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path == '/admin/reviews/hidden') {
        return http.Response(
          jsonEncode({
            'items': [
              {'id': 'r2', 'rating': 1, 'text': 'y'},
            ],
            'total': 1,
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'moderationStatus': 'visible'}), 200);
    }));
    await p.loadHidden();
    expect(p.hidden, hasLength(1));
    expect(await p.restore('r2'), isTrue);
    expect(p.hidden, isEmpty);
  });

  test('surfaces an action error and keeps the row', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path == '/admin/reviews/reports') {
        return http.Response(
          jsonEncode({
            'items': [
              {'reviewId': 'r1', 'rating': 1, 'text': 'x', 'reportCount': 1},
            ],
            'total': 1,
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'error': 'forbidden'}), 403);
    }));
    await p.loadReported();
    expect(await p.hide('r1', 'x'), isFalse);
    expect(p.reported, hasLength(1));
    expect(p.actionError, isNotNull);
  });
}
