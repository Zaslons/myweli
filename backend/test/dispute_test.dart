import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/admin/dispute_service.dart';
import 'package:myweli_backend/src/admin/disputes_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryDisputesRepository disputes;
  late InMemoryAppointmentRepository appts;
  late InMemoryAuditLogRepository audit;
  late DisputeService svc;

  Future<void> seedAppt(String id, {String? screenshot}) => appts.create({
    'id': id,
    'userId': 'user_A',
    'providerId': 'provider1',
    'serviceIds': ['service1'],
    'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
    'status': 'confirmed',
    'totalPrice': 15000,
    'depositAmount': 4500,
    'balanceDue': 10500,
    'depositScreenshotUrl': screenshot,
    'createdAt': DateTime.utc(2030).toIso8601String(),
  });

  setUp(() {
    disputes = InMemoryDisputesRepository();
    appts = InMemoryAppointmentRepository();
    audit = InMemoryAuditLogRepository();
    final providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    final deposit = DepositService(
      appts,
      MembershipService(InMemoryMembershipRepository(), providerAuth),
      const FakeStorageService(),
    );
    svc = DisputeService(disputes, appts, deposit, audit);
  });

  test('open requires an existing booking + reason; audits', () async {
    await seedAppt('a1');
    expect((await svc.open('admin_1', 'a1', '')).error, 'invalid_input');
    expect((await svc.open('admin_1', 'nope', 'x')).error, 'not_found');

    final r = await svc.open('admin_1', 'a1', 'Client says no-show was unfair');
    expect((r.data! as Map)['status'], 'open');
    expect((await audit.list()).items.first['action'], 'dispute.open');
  });

  test(
    'detail returns the booking + a signed deposit-screenshot URL',
    () async {
      await seedAppt('a1', screenshot: 'deposit/user_A/x.jpg');
      final opened = (await svc.open('admin_1', 'a1', 'r')).data! as Map;
      final d =
          (await svc.detail('admin_1', opened['id'] as String)).data! as Map;
      expect((d['dispute'] as Map)['id'], opened['id']);
      expect((d['appointment'] as Map)['id'], 'a1');
      expect(d['depositScreenshotUrl'], isNotNull); // admin can see the proof
    },
  );

  test('resolve requires a resolution + records the outcome; audits', () async {
    await seedAppt('a1');
    final opened = (await svc.open('admin_1', 'a1', 'r')).data! as Map;
    expect(
      (await svc.resolve('admin_1', opened['id'] as String, '')).error,
      'invalid_input',
    );
    final r = await svc.resolve(
      'admin_1',
      opened['id'] as String,
      'Salon to refund the deposit',
    );
    expect((r.data! as Map)['status'], 'resolved');
    expect((r.data! as Map)['resolution'], 'Salon to refund the deposit');
    // Queue of open disputes is now empty.
    expect(((await svc.list(status: 'open')).data! as Map)['total'], 0);
    expect((await audit.list()).items.first['action'], 'dispute.resolve');
    expect((await svc.resolve('admin_1', 'nope', 'x')).error, 'not_found');
  });
}
