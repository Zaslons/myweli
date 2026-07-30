import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/pro_membership.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// Team access R4b — the mock world's role simulation: getMyProvider per
/// seeded account, the field-gated dashboard, and the staff own-filters
/// (mirrors the R4a server so the demo behaves like prod).
void main() {
  final auth = MockAuthService();
  final pro = MockProService();

  setUpAll(() {
    serviceLocator.authService = auth;
  });

  setUp(() async {
    MockData.resetTeam();
    await auth.logoutProvider();
  });

  Future<void> loginAs(String email) async {
    await auth.requestProviderEmailOtp(email);
    final res =
        await auth.verifyProviderEmailOtp(email, MockAuthService.demoOtp);
    expect(res.signedIn, isTrue, reason: 'mock login as $email failed');
  }

  test(
      'getMyProvider: manager / réception / staff resolve their roster '
      'role over provider1', () async {
    await loginAs('awa.manager@myweli.test');
    var info = (await pro.getMyProvider()).data!;
    expect(info.membership.role, TeamRole.manager);
    expect(info.salon.id, 'provider1');
    expect(info.membership.can(ProCap.financesView), isFalse);

    await loginAs('fatou.reception@myweli.test');
    info = (await pro.getMyProvider()).data!;
    expect(info.membership.role, TeamRole.reception);
    expect(info.membership.can(ProCap.clientsView), isTrue);
    expect(info.membership.can(ProCap.catalogueManage), isFalse);

    await loginAs('sonia.staff@myweli.test');
    info = (await pro.getMyProvider()).data!;
    expect(info.membership.role, TeamRole.staff);
    expect(info.membership.artistId, 'artist1');
  });

  test('a revoked member gets not_a_member (the revoked signal)', () async {
    await loginAs('sonia.staff@myweli.test');
    final i = MockData.teamMembers.indexWhere((m) => m.id == 'mem_staff2');
    MockData.teamMembers[i] = MockData.teamMembers[i].copyWith(
      status: TeamMemberStatus.revoked,
      revokedAt: DateTime.now(),
    );
    final res = await pro.getMyProvider();
    expect(res.success, isFalse);
    expect(res.code, 'not_a_member');
  });

  test('the dashboard field-gates money for non-finance roles (R1 mirror)',
      () async {
    await loginAs('awa.manager@myweli.test');
    final stats = (await pro.getDashboardStats('provider1')).data!;
    expect(stats.hasRevenue, isFalse);
    expect(stats.todayRevenue, isNull);
    expect(stats.totalAppointments, greaterThanOrEqualTo(0));
  });

  test('staff journal + list are own-artist filtered (T40 mirror)', () async {
    await loginAs('sonia.staff@myweli.test');
    final day = (await pro.getJournalDay('provider1', DateTime.now())).data!;
    expect(
      day.appointments.every((a) => a.artistId == 'artist1'),
      isTrue,
    );
    final list = (await pro.getProviderAppointments('provider1')).data!;
    expect(list.every((a) => a.artistId == 'artist1'), isTrue);
  });

  test('an OWNER session keeps the full world (no filters, revenue on)',
      () async {
    await auth.requestProviderEmailOtp('own2@r4b.test');
    await auth.registerProviderWithEmail(
      email: 'own2@r4b.test',
      code: MockAuthService.demoOtp,
      phoneNumber: '+2250700000098',
      businessName: 'Salon R4b 2',
      businessType: BusinessType.salon,
    );
    final stats = (await pro.getDashboardStats('provider1')).data!;
    expect(stats.hasRevenue, isTrue);
  });
}
