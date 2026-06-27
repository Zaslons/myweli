import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_notification_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

void main() {
  late InMemorySessionStore store;

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  ApiNotificationService svc(MockClient c) => ApiNotificationService(
        client: c,
        baseUrl: 'http://x',
        sessionStore: store,
      );

  test('getNotifications parses the feed', () async {
    final s = svc(MockClient((req) async {
      expect(req.url.path, '/me/notifications');
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'n1',
              'type': 'bookingConfirmed',
              'title': 'Confirmé',
              'body': 'x',
              'createdAt': '2026-06-28T10:00:00.000Z',
              'read': false,
              'route': '/bookings',
            },
          ],
        }),
        200,
      );
    }));
    final res = await s.getNotifications();
    expect(res.success, isTrue);
    expect(res.data!.single.title, 'Confirmé');
    expect(res.data!.single.route, '/bookings');
  });

  test('markRead / markAllRead POST the right paths', () async {
    final paths = <String>[];
    final s = svc(MockClient((req) async {
      paths.add('${req.method} ${req.url.path}');
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    }));
    expect((await s.markRead('n1')).success, isTrue);
    expect((await s.markAllRead()).success, isTrue);
    expect(paths, [
      'POST /me/notifications/n1/read',
      'POST /me/notifications/read-all',
    ]);
  });

  test('getPreferences parses prefs', () async {
    final s = svc(MockClient((req) async {
      expect(req.url.path, '/me/notification-preferences');
      return http.Response(
        jsonEncode({'reminders': false, 'marketing': true, 'push': true}),
        200,
      );
    }));
    final res = await s.getPreferences();
    expect(res.success, isTrue);
    expect(res.data!.reminders, isFalse);
    expect(res.data!.marketing, isTrue);
  });

  test('updatePreferences PUTs only the changed fields', () async {
    String? method;
    Map<String, dynamic>? sent;
    final s = svc(MockClient((req) async {
      method = req.method;
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'reminders': false, 'marketing': true, 'push': true}),
        200,
      );
    }));
    final res = await s.updatePreferences(reminders: false);
    expect(res.success, isTrue);
    expect(method, 'PUT');
    expect(sent, {'reminders': false});
  });

  test('not connected → error (no token)', () async {
    final s = ApiNotificationService(
      client: MockClient((_) async => http.Response('{}', 200)),
      baseUrl: 'http://x',
      sessionStore: InMemorySessionStore(), // empty → no token
    );
    expect((await s.getNotifications()).success, isFalse);
  });
}
