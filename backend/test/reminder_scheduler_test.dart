import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_outbox_repository.dart';
import 'package:myweli_backend/src/messaging/messaging_prefs_repository.dart';
import 'package:myweli_backend/src/messaging/messaging_provider.dart';
import 'package:myweli_backend/src/messaging/messaging_service.dart';
import 'package:myweli_backend/src/messaging/reminder_log_repository.dart';
import 'package:myweli_backend/src/messaging/reminder_scheduler.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements AuthRepository {}

class _MockProviders extends Mock implements ProvidersRepository {}

void main() {
  final now = DateTime.utc(2026, 6, 28, 12);

  late InMemoryAppointmentRepository appts;
  late InMemoryMessagingOutboxRepository outbox;
  late ReminderScheduler scheduler;

  Future<void> seed(String id, String status, DateTime at) => appts.create({
    'id': id,
    'status': status,
    'appointmentDate': at.toIso8601String(),
    'providerId': 'p1',
    'clientPhone': '+225070000000$id',
  });

  setUp(() async {
    appts = InMemoryAppointmentRepository();
    outbox = InMemoryMessagingOutboxRepository();
    final providers = _MockProviders();
    when(() => providers.byId(any())).thenAnswer((_) async => null);
    final notifier = BookingNotifier(
      MessagingService(
        LogMessagingProvider(),
        outbox,
        InMemoryMessagingPrefsRepository(),
      ),
      _MockAuth(),
      providers,
      PushService(LogPushProvider(), InMemoryDeviceTokenRepository()),
      InMemoryNotificationsRepository(),
    );
    scheduler = ReminderScheduler(
      appts,
      InMemoryReminderLogRepository(),
      notifier,
    );
    await seed('1', 'confirmed', now.add(const Duration(hours: 1))); // 24h + 2h
    await seed(
      '2',
      'confirmed',
      now.add(const Duration(hours: 12)),
    ); // 24h only
    await seed('3', 'confirmed', now.add(const Duration(hours: 30))); // none
    await seed('4', 'pending', now.add(const Duration(hours: 1))); // ignored
  });

  test(
    'first tick sends 24h for both in-window + 2h for the imminent one',
    () async {
      final r = await scheduler.tick(now);
      expect(r.reminder24h, 2); // appts 1 + 2
      expect(r.reminder2h, 1); // appt 1 (within 2h)
      expect((await outbox.list()).total, 3);
    },
  );

  test('a second tick is idempotent (no re-sends)', () async {
    await scheduler.tick(now);
    final r2 = await scheduler.tick(now);
    expect(r2.reminder24h, 0);
    expect(r2.reminder2h, 0);
    expect((await outbox.list()).total, 3);
  });
}
