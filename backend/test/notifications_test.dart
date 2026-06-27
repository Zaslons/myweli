import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/messaging_outbox_repository.dart';
import 'package:myweli_backend/src/messaging/messaging_prefs_repository.dart';
import 'package:myweli_backend/src/messaging/messaging_provider.dart';
import 'package:myweli_backend/src/messaging/messaging_service.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:test/test.dart';

import '../routes/me/notifications/[id]/read.dart' as read_route;
import '../routes/me/notifications/index.dart' as list_route;
import '../routes/me/notifications/read-all.dart' as read_all_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('InMemoryNotificationsRepository', () {
    late InMemoryNotificationsRepository repo;
    setUp(() => repo = InMemoryNotificationsRepository());

    test(
      'add + listForUser (scoped, newest first); markRead; markAllRead',
      () async {
        await repo.add(userId: 'u1', type: 'reminder', title: 'A', body: 'a');
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final n2 = await repo.add(
          userId: 'u1',
          type: 'general',
          title: 'B',
          body: 'b',
        );
        await repo.add(userId: 'u2', type: 'general', title: 'C', body: 'c');

        final mine = await repo.listForUser('u1');
        expect(mine.map((n) => n['title']), ['B', 'A']); // newest first, scoped

        // markRead is scoped: u2 can't mark u1's notification.
        expect(await repo.markRead('u2', n2['id'] as String), isFalse);
        expect(await repo.markRead('u1', n2['id'] as String), isTrue);
        expect(
          (await repo.listForUser(
            'u1',
          )).firstWhere((n) => n['id'] == n2['id'])['read'],
          isTrue,
        );

        await repo.markAllRead('u1');
        expect(
          (await repo.listForUser('u1')).every((n) => n['read'] == true),
          isTrue,
        );
      },
    );
  });

  group('routes /me/notifications', () {
    final tokens = TokenService(secret: 'test-secret');
    late InMemoryNotificationsRepository repo;

    setUp(() => repo = InMemoryNotificationsRepository());

    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<NotificationsRepository>()).thenReturn(repo);
      return context;
    }

    Request req(String method, String path, {String? token}) => Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub) =>
        tokens.issueAccessToken(subject: sub, role: 'user').token;

    test('list returns only the caller; anon → 401', () async {
      await repo.add(userId: 'u1', type: 'general', title: 'Mine', body: 'x');
      await repo.add(userId: 'u2', type: 'general', title: 'Theirs', body: 'y');

      final res = await list_route.onRequest(
        ctx(req('GET', '/me/notifications', token: tok('u1'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final items = (await res.json() as Map)['items'] as List;
      expect(items.map((n) => (n as Map)['title']), ['Mine']);

      final anon = await list_route.onRequest(
        ctx(req('GET', '/me/notifications')),
      );
      expect(anon.statusCode, HttpStatus.unauthorized);
    });

    test('mark one read → 200; foreign id → 404; read-all clears', () async {
      final n = await repo.add(
        userId: 'u1',
        type: 'general',
        title: 'X',
        body: 'x',
      );
      await repo.add(userId: 'u2', type: 'general', title: 'Y', body: 'y');

      final ok = await read_route.onRequest(
        ctx(req('POST', '/me/notifications/${n['id']}/read', token: tok('u1'))),
        n['id'] as String,
      );
      expect(ok.statusCode, HttpStatus.ok);

      // u1 can't mark u2's (404).
      final foreign = await read_route.onRequest(
        ctx(req('POST', '/me/notifications/nope/read', token: tok('u1'))),
        'nope',
      );
      expect(foreign.statusCode, HttpStatus.notFound);

      await read_all_route.onRequest(
        ctx(req('POST', '/me/notifications/read-all', token: tok('u1'))),
      );
      expect(
        (await repo.listForUser('u1')).every((x) => x['read'] == true),
        isTrue,
      );
    });
  });

  group('BookingNotifier → in-app feed', () {
    test(
      'a lifecycle event writes a notification for the booking user',
      () async {
        final notifications = InMemoryNotificationsRepository();
        final notifier = BookingNotifier(
          MessagingService(
            LogMessagingProvider(),
            InMemoryMessagingOutboxRepository(),
            InMemoryMessagingPrefsRepository(),
          ),
          InMemoryAuthRepository(
            tokens: TokenService(secret: 'x'),
            isProd: false,
          ),
          InMemoryProvidersRepository(),
          PushService(LogPushProvider(), InMemoryDeviceTokenRepository()),
          notifications,
          InMemoryNotificationPrefsRepository(),
        );

        await notifier.notify({
          'id': 'a1',
          'userId': 'u1',
          'providerId': 'provider1',
          'appointmentDate': '2026-06-28T10:00:00.000Z',
        }, MessageTemplate.bookingConfirmed);

        final feed = await notifications.listForUser('u1');
        expect(feed, hasLength(1));
        expect(feed.first['type'], 'bookingConfirmed');
        expect(feed.first['route'], '/bookings');

        // Manual booking (no userId) → no in-app entry.
        await notifier.notify({
          'id': 'a2',
          'clientPhone': '+2250700000000',
          'providerId': 'provider1',
        }, MessageTemplate.cancelled);
        expect(await notifications.listForUser('u1'), hasLength(1));
      },
    );
  });
}
