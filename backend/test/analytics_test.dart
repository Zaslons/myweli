import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/admin/analytics_service.dart';
import 'package:myweli_backend/src/admin/disputes_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

void main() {
  final tokens = TokenService(secret: 'test-secret');

  test('overview aggregates bookings, rates, providers + disputes', () async {
    final appts = InMemoryAppointmentRepository();
    final providers = InMemoryProvidersRepository();
    final auth = InMemoryAuthRepository(tokens: tokens, echoDevCode: true);
    final providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
    );
    final disputes = InMemoryDisputesRepository();
    final reviews = InMemoryReviewsRepository();

    Future<void> appt(String id, String status) => appts.create({
      'id': id,
      'userId': 'u1',
      'providerId': 'provider1',
      'serviceIds': ['s1'],
      'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
      'status': status,
      'totalPrice': 10000,
      'createdAt': DateTime.utc(2030).toIso8601String(),
    });
    // 2 completed, 1 no-show, 1 cancelled → noShowRate 1/3, cancelRate 1/4.
    await appt('a1', 'completed');
    await appt('a2', 'completed');
    await appt('a3', 'noShow');
    await appt('a4', 'cancelled');
    // One suspended provider (provider2 exists in the seed).
    await providers.setStatus('provider2', 'suspended');
    await disputes.create(
      appointmentId: 'a1',
      openedBy: 'admin_1',
      reason: 'x',
    );

    final svc = AnalyticsService(
      appts,
      providers,
      auth,
      providerAuth,
      disputes,
      reviews,
      validations: InMemorySalonValidationRepository(
        providers: providers,
        members: InMemoryMembershipRepository(),
      ),
    );
    final data = (await svc.overview()).data! as Map;

    final bookings = data['bookings'] as Map;
    expect(bookings['completed'], 2);
    expect(bookings['noShow'], 1);
    expect(bookings['total'], 4);

    final guard = data['guardrails'] as Map;
    expect(guard['noShowRate'], closeTo(0.333, 0.001)); // 1 / (2+1)
    expect(guard['cancellationRate'], 0.25); // 1 / 4

    final provs = data['providers'] as Map;
    expect(provs['suspended'], 1);
    expect(provs['active'], greaterThanOrEqualTo(3));

    expect((data['disputes'] as Map)['open'], 1);
  });

  test('providers.pendingValidation is the queue\'s pending count — '
      'suspended salons left out, one definition (B0.18 §3.5)', () async {
    final providers = InMemoryProvidersRepository([]);
    final validations = InMemorySalonValidationRepository(
      providers: providers,
      members: InMemoryMembershipRepository(),
    );
    Future<String> asked() async {
      final s = await providers.createSalon(
        name: 'Salon ${DateTime.now().microsecondsSinceEpoch}',
        category: 'salon',
        phoneNumber: '+2250700000009',
      );
      final id = s['id'] as String;
      await validations.submit(id, DateTime.utc(2026, 11, 12));
      return id;
    }

    await asked();
    await asked();
    final suspended = await asked();
    await providers.setStatus(suspended, 'suspended');

    final svc = AnalyticsService(
      InMemoryAppointmentRepository(),
      providers,
      InMemoryAuthRepository(tokens: tokens, echoDevCode: true),
      InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true),
      InMemoryDisputesRepository(),
      InMemoryReviewsRepository(),
      validations: validations,
    );
    final data = (await svc.overview()).data! as Map;
    expect((data['providers'] as Map)['pendingValidation'], 2);
    expect(
      (data['providers'] as Map)['pendingValidation'],
      (await validations.queue('pending')).total,
      reason: 'the sidebar and the dashboard read one number',
    );
  });

  test('northStar buckets completed bookings by week × commune', () async {
    final appts = InMemoryAppointmentRepository();
    final providers = InMemoryProvidersRepository();
    final auth = InMemoryAuthRepository(tokens: tokens, echoDevCode: true);
    final providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
    );
    final disputes = InMemoryDisputesRepository();
    final reviews = InMemoryReviewsRepository();

    // provider1 = Cocody, provider3 = Yopougon (from the seed). Two completed
    // in the same recent week for provider1, one for provider3.
    final base = DateTime.now().toUtc().subtract(const Duration(days: 2));
    Future<void> done(String id, String providerId) => appts.create({
      'id': id,
      'userId': 'u1',
      'providerId': providerId,
      'serviceIds': ['s1'],
      'appointmentDate': base.toIso8601String(),
      'status': 'completed',
      'totalPrice': 10000,
      'createdAt': base.toIso8601String(),
    });
    await done('a1', 'provider1');
    await done('a2', 'provider1');
    await done('a3', 'provider3');
    // An old completed booking (outside the window) is excluded.
    await appts.create({
      'id': 'old',
      'userId': 'u1',
      'providerId': 'provider1',
      'serviceIds': ['s1'],
      'appointmentDate': DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 400))
          .toIso8601String(),
      'status': 'completed',
      'totalPrice': 10000,
      'createdAt': base.toIso8601String(),
    });

    final svc = AnalyticsService(
      appts,
      providers,
      auth,
      providerAuth,
      disputes,
      reviews,
      validations: InMemorySalonValidationRepository(
        providers: providers,
        members: InMemoryMembershipRepository(),
      ),
    );
    final data = (await svc.northStar(weeks: 4)).data! as Map;

    expect(data['totalCompleted'], 3); // the 400-days-old one is excluded
    final series = (data['series'] as List).cast<Map<String, dynamic>>();
    final cocody = series.firstWhere((e) => e['commune'] == 'Cocody');
    final yop = series.firstWhere((e) => e['commune'] == 'Yopougon');
    expect(cocody['completed'], 2);
    expect(yop['completed'], 1);
  });
}
