import 'package:myweli_backend/src/admin/admin_user_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryAuthRepository auth;
  late InMemoryAppointmentRepository appts;
  late InMemoryAuditLogRepository audit;
  late AdminUserService svc;

  Future<String> createUser(String phone) async {
    final req = await auth.requestOtp(phone);
    final v = await auth.verifyOtp(phone, req.devCode!);
    return v.user!.id;
  }

  setUp(() {
    auth = InMemoryAuthRepository(tokens: tokens, isProd: false);
    appts = InMemoryAppointmentRepository();
    audit = InMemoryAuditLogRepository();
    svc = AdminUserService(auth, appts, audit);
  });

  test('ban blocks login; unban restores it; both audited', () async {
    const phone = '+2250700000001';
    final id = await createUser(phone);

    final r = await svc.ban('admin_1', id, 'abuse');
    expect((r.data! as Map)['status'], 'banned');
    expect((await audit.list()).items.first['action'], 'user.ban');

    // A banned user can't complete login.
    final req = await auth.requestOtp(phone);
    final v = await auth.verifyOtp(phone, req.devCode!);
    expect(v.error, 'account_suspended');

    // Unban → login works again.
    await svc.unban('admin_1', id);
    final req2 = await auth.requestOtp(phone);
    final v2 = await auth.verifyOtp(phone, req2.devCode!);
    expect(v2.ok, isTrue);
  });

  test('list filters by status; detail includes bookings; not_found', () async {
    final id = await createUser('+2250700000002');
    await svc.ban('admin_1', id, 'x');

    final banned = (await svc.list(status: 'banned')).data! as Map;
    expect((banned['items'] as List).length, 1);
    expect((banned['items'] as List).first['status'], 'banned');

    final detail = (await svc.detail(id)).data! as Map;
    expect(detail['id'], id);
    expect(detail.containsKey('recentAppointments'), isTrue);

    expect((await svc.detail('nope')).error, 'not_found');
  });
}
