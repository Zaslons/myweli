import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
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

class _MockAuth extends Mock implements AuthRepository {}

class _MockProviders extends Mock implements ProvidersRepository {}

/// Captures the FCM payload so the deep-link route can be asserted.
class _RecordingPushProvider implements PushProvider {
  final sends = <Map<String, String>>[];

  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    sends.add(data);
    return (sent: tokens.length, invalidTokens: const <String>[]);
  }
}

void main() {
  late InMemoryMessagingOutboxRepository outbox;
  late MessagingService messaging;
  late _MockAuth users;
  late _MockProviders providers;

  setUp(() {
    outbox = InMemoryMessagingOutboxRepository();
    messaging = MessagingService(
      LogMessagingProvider(),
      outbox,
      InMemoryMessagingPrefsRepository(),
    );
    users = _MockAuth();
    providers = _MockProviders();
    when(
      () => providers.byId(any()),
    ).thenAnswer((_) async => {'name': 'Beauté Divine'});
  });

  BookingNotifier notifier() => BookingNotifier(
    messaging,
    users,
    providers,
    PushService(LogPushProvider(), InMemoryDeviceTokenRepository()),
    InMemoryNotificationsRepository(),
    InMemoryNotificationPrefsRepository(),
  );

  test('the consumer push carries the deep-link route; the feed row keeps '
      '/bookings (the web center maps that path)', () async {
    final pushes = _RecordingPushProvider();
    final devices = InMemoryDeviceTokenRepository();
    await devices.upsert(
      token: 'tok-u1',
      userId: 'u1',
      role: 'user',
      platform: 'android',
    );
    final feed = InMemoryNotificationsRepository();
    when(() => users.userById('u1')).thenAnswer(
      (_) async => AuthUser(
        id: 'u1',
        phoneNumber: '+2250700000002',
        createdAt: DateTime.utc(2026),
      ),
    );

    await BookingNotifier(
      messaging,
      users,
      providers,
      PushService(pushes, devices),
      feed,
      InMemoryNotificationPrefsRepository(),
    ).notify({
      'id': 'a7',
      'providerId': 'p1',
      'userId': 'u1',
      'appointmentDate': '2026-06-28T09:00:00.000Z',
    }, MessageTemplate.bookingAccepted);

    expect(pushes.sends.single['route'], '/appointment/a7');
    expect(pushes.sends.single['appointmentId'], 'a7');
    expect(pushes.sends.single['template'], 'bookingAccepted');
    expect((await feed.listForUser('u1')).single['route'], '/bookings');
  });

  test('message times render the SALON wall-clock; amounts read FCFA '
      '(multi-pays MP1)', () async {
    when(() => providers.byId(any())).thenAnswer(
      (_) async => {
        'name': 'Institut Libreville',
        'timezone': 'Africa/Libreville', // UTC+1
        'currency': 'XAF',
      },
    );
    await notifier().notify({
      'id': 'lbv1',
      'providerId': 'p9',
      'clientPhone': '+2410700000001',
      'appointmentDate': '2026-06-28T09:00:00.000Z', // = 10:00 Libreville
      'depositAmount': 5000,
    }, MessageTemplate.bookingConfirmed);
    final row = (await outbox.list()).items.single;
    final body = row['body'] as String;
    expect(body, contains('10:00')); // salon wall-clock, not 09:00Z
    expect(body, contains('5000 FCFA')); // XAF reads FCFA, never « XOF »
  });

  test('uses clientPhone (manual booking) without a user lookup', () async {
    await notifier().notify({
      'id': 'a1',
      'providerId': 'p1',
      'clientPhone': '+2250700000001',
      'appointmentDate': '2026-06-28T14:30:00.000Z',
      'depositAmount': 5000,
    }, MessageTemplate.bookingConfirmed);
    final row = (await outbox.list()).items.single;
    expect(row['recipientPhone'], '+2250700000001');
    expect(row['template'], 'bookingConfirmed');
    expect(row['body'], contains('Beauté Divine'));
    expect(row['body'], contains('28/06/2026'));
    verifyNever(() => users.userById(any()));
  });

  test('resolves the consumer phone via userId when no clientPhone', () async {
    when(() => users.userById('u1')).thenAnswer(
      (_) async => AuthUser(
        id: 'u1',
        phoneNumber: '+2250700000002',
        createdAt: DateTime.utc(2026),
      ),
    );
    await notifier().notify({
      'id': 'a2',
      'providerId': 'p1',
      'userId': 'u1',
      'appointmentDate': '2026-06-28T09:00:00.000Z',
    }, MessageTemplate.cancelled);
    final row = (await outbox.list()).items.single;
    expect(row['recipientPhone'], '+2250700000002');
    expect(row['template'], 'cancelled');
  });

  test('no recipient → no message; null appointment → no-op', () async {
    when(() => users.userById('ghost')).thenAnswer((_) async => null);
    await notifier().notify({
      'id': 'a3',
      'providerId': 'p1',
      'userId': 'ghost',
    }, MessageTemplate.cancelled);
    await notifier().notify(null, MessageTemplate.cancelled);
    expect((await outbox.list()).total, 0);
  });
}
