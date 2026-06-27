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
