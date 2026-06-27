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

import '../routes/me/notification-preferences/index.dart' as prefs_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockAuth extends Mock implements AuthRepository {}

class _MockProviders extends Mock implements ProvidersRepository {}

/// Records how many device-push sends BookingNotifier attempts (no network).
class _RecordingPush extends PushService {
  _RecordingPush() : super(LogPushProvider(), InMemoryDeviceTokenRepository());
  int calls = 0;

  @override
  Future<int> sendToUser(
    String userId, {
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    calls++;
    return 0;
  }
}

void main() {
  group('InMemoryNotificationPrefsRepository', () {
    late InMemoryNotificationPrefsRepository repo;
    setUp(() => repo = InMemoryNotificationPrefsRepository());

    test('absent user → all-true defaults', () async {
      final p = await repo.get('u1');
      expect(p.reminders, isTrue);
      expect(p.marketing, isTrue);
      expect(p.push, isTrue);
    });

    test('update merges only provided fields', () async {
      await repo.update('u1', reminders: false);
      var p = await repo.get('u1');
      expect(p.reminders, isFalse);
      expect(p.marketing, isTrue);
      expect(p.push, isTrue);

      await repo.update('u1', push: false);
      p = await repo.get('u1');
      expect(p.reminders, isFalse); // preserved
      expect(p.push, isFalse);
    });
  });

  group('routes /me/notification-preferences', () {
    final tokens = TokenService(secret: 'test-secret');
    late InMemoryNotificationPrefsRepository repo;
    setUp(() => repo = InMemoryNotificationPrefsRepository());

    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<NotificationPrefsRepository>()).thenReturn(repo);
      return c;
    }

    Request req(String method, {String? token, String? body}) => Request(
      method,
      Uri.parse('http://localhost/me/notification-preferences'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      body: body,
    );

    String tok(String sub) =>
        tokens.issueAccessToken(subject: sub, role: 'user').token;

    test('GET returns defaults; anon → 401', () async {
      final res = await prefs_route.onRequest(
        ctx(req('GET', token: tok('u1'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      expect((await res.json() as Map)['reminders'], isTrue);

      final anon = await prefs_route.onRequest(ctx(req('GET')));
      expect(anon.statusCode, HttpStatus.unauthorized);
    });

    test('PUT partial update persists + returns merged', () async {
      final res = await prefs_route.onRequest(
        ctx(req('PUT', token: tok('u1'), body: '{"reminders":false}')),
      );
      expect(res.statusCode, HttpStatus.ok);
      final m = await res.json() as Map;
      expect(m['reminders'], isFalse);
      expect(m['marketing'], isTrue);
      expect((await repo.get('u1')).reminders, isFalse);
    });

    test('PUT non-bool field → 400', () async {
      final res = await prefs_route.onRequest(
        ctx(req('PUT', token: tok('u1'), body: '{"push":"nope"}')),
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('PUT invalid json → 400', () async {
      final res = await prefs_route.onRequest(
        ctx(req('PUT', token: tok('u1'), body: 'not json')),
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('unsupported verb → 405', () async {
      final res = await prefs_route.onRequest(
        ctx(req('DELETE', token: tok('u1'))),
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('BookingNotifier honours prefs', () {
    late InMemoryMessagingOutboxRepository outbox;
    late MessagingService messaging;
    late _MockAuth users;
    late _MockProviders providers;
    late _RecordingPush push;
    late InMemoryNotificationsRepository feed;
    late InMemoryNotificationPrefsRepository prefs;

    setUp(() {
      outbox = InMemoryMessagingOutboxRepository();
      messaging = MessagingService(
        LogMessagingProvider(),
        outbox,
        InMemoryMessagingPrefsRepository(),
      );
      users = _MockAuth();
      providers = _MockProviders();
      push = _RecordingPush();
      feed = InMemoryNotificationsRepository();
      prefs = InMemoryNotificationPrefsRepository();
      when(() => providers.byId(any())).thenAnswer((_) async => {'name': 'X'});
      when(() => users.userById('u1')).thenAnswer(
        (_) async => AuthUser(
          id: 'u1',
          phoneNumber: '+2250700000001',
          createdAt: DateTime.utc(2026),
        ),
      );
    });

    BookingNotifier notifier() =>
        BookingNotifier(messaging, users, providers, push, feed, prefs);

    Map<String, dynamic> appt() => {
      'id': 'a1',
      'userId': 'u1',
      'providerId': 'p1',
      'appointmentDate': '2026-06-28T10:00:00.000Z',
    };

    test('reminders off → no reminder message/push, feed entry kept', () async {
      await prefs.update('u1', reminders: false);
      await notifier().notify(appt(), MessageTemplate.reminder24h);
      expect((await outbox.list()).total, 0);
      expect(push.calls, 0);
      expect((await feed.listForUser('u1')).length, 1);
    });

    test('push off → no push, message still sent', () async {
      await prefs.update('u1', push: false);
      await notifier().notify(appt(), MessageTemplate.bookingConfirmed);
      expect((await outbox.list()).total, 1);
      expect(push.calls, 0);
    });

    test('marketing off → promotional message skipped', () async {
      await prefs.update('u1', marketing: false);
      await notifier().notify(appt(), MessageTemplate.rebookReminder);
      expect((await outbox.list()).total, 0);
    });

    test('all on (default) → message + push sent', () async {
      await notifier().notify(appt(), MessageTemplate.bookingConfirmed);
      expect((await outbox.list()).total, 1);
      expect(push.calls, 1);
    });
  });
}
