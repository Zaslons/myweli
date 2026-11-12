import 'dart:convert';

import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appts;
  late InMemoryAuditLogRepository audit;
  late InMemoryProviderAuthRepository providerAuthStub;
  late InMemoryMembershipRepository members;
  late InMemorySalonSubscriptionRepository subs;
  late AdminProviderService svc;

  setUp(() {
    // A copy of the seed, never the shared mutable `seedProviders`: a
    // suspension left behind by one test would be a re-suspension in the
    // next, which keeps no `suspended_from` (B0.18 §3.4).
    providers = InMemoryProvidersRepository(
      (jsonDecode(jsonEncode(seedProviders)) as List)
          .cast<Map<String, dynamic>>(),
    );
    appts = InMemoryAppointmentRepository();
    audit = InMemoryAuditLogRepository();
    providerAuthStub = InMemoryProviderAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      echoDevCode: true,
    );
    members = InMemoryMembershipRepository();
    subs = InMemorySalonSubscriptionRepository();
    svc = AdminProviderService(
      providers,
      appts,
      audit,
      SalonSubscriptionService(
        subs,
        MembershipService(members, providerAuthStub),
        members,
        providers,
        providerAuthStub,
      ),
      // The seed's active salons are validated and live (§3.7's in-memory
      // mirror of the dev backfill).
      validations: InMemorySalonValidationRepository(
        providers: providers,
        members: members,
      ),
      members: members,
    );
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

  test('restore lifts the suspension — of a validated, live salon with an '
      'owner and a live offer (B0.18 §3.4)', () async {
    // What « back online » now takes: an active owner and a live offer row
    // beside the seed's validation. Without them restore lifts to draft —
    // salon_validation_bypasses_test.dart has each reason.
    await members.ensureOwner(
      providerId: 'provider1',
      accountId: 'acc_owner_1',
      email: 'owner@beaute-divine.ci',
    );
    await subs.create(
      providerId: 'provider1',
      tier: 'pro',
      trialEndsAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );
    await svc.suspend('admin_1', 'provider1', 'x');
    final r = await svc.restore('admin_1', 'provider1');
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(r.data, {'status': 'active', 'reason': null});
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
