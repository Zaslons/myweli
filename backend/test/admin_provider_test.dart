import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appts;
  late InMemoryAuditLogRepository audit;
  late AdminProviderService svc;

  setUp(() {
    providers = InMemoryProvidersRepository();
    appts = InMemoryAppointmentRepository();
    audit = InMemoryAuditLogRepository();
    svc = AdminProviderService(providers, appts, audit);
  });

  test(
    'suspend hides from discovery + blocks booking; login unaffected',
    () async {
      // provider1 is discoverable initially.
      expect(
        (await providers.query()).map((p) => p['id']),
        contains('provider1'),
      );

      final r = await svc.suspend('admin_1', 'provider1', 'fraud review');
      expect((r.data! as Map)['status'], 'suspended');

      // Gone from discovery.
      expect(
        (await providers.query()).map((p) => p['id']),
        isNot(contains('provider1')),
      );
      // Booking rejected.
      final booking = BookingService(
        providers,
        appts,
        SlotService(providers, appts),
      );
      final book = await booking.book(
        userId: 'u1',
        providerId: 'provider1',
        serviceIds: const ['service1'],
        appointmentDateTime: DateTime.utc(2030, 6, 10, 9),
      );
      expect(book.error, 'provider_suspended');
      // Audited.
      expect((await audit.list()).items.first['action'], 'provider.suspend');
    },
  );

  test('restore lifts the suspension', () async {
    await svc.suspend('admin_1', 'provider1', 'x');
    await svc.restore('admin_1', 'provider1');
    expect(
      (await providers.query()).map((p) => p['id']),
      contains('provider1'),
    );
    expect((await audit.list()).items.first['action'], 'provider.restore');
  });

  test('feature puts the provider first in discovery', () async {
    // provider1 has the top rating; feature a lower-rated one to test ordering.
    await svc.feature('admin_1', 'provider4', true);
    expect((await providers.query()).first['id'], 'provider4');
    final log = await audit.list();
    expect(log.items.first['action'], 'provider.feature');
    expect((log.items.first['metadata'] as Map)['featured'], true);
    // Bad payload → invalid_input.
    expect(
      (await svc.feature('admin_1', 'provider4', 'yes')).error,
      'invalid_input',
    );
  });

  test('list filters by status; detail includes recent bookings', () async {
    await svc.suspend('admin_1', 'provider2', 'x');
    final suspended = (await svc.list(status: 'suspended')).data! as Map;
    expect((suspended['items'] as List).map((p) => p['id']), ['provider2']);

    final detail = (await svc.detail('provider1')).data! as Map;
    expect(detail['id'], 'provider1');
    expect(detail.containsKey('recentAppointments'), isTrue);
    expect((await svc.detail('nope')).error, 'not_found');
  });
}
