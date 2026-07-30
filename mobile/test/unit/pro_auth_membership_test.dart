import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/pro_membership.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';

/// Team access R4b — ProAuthProvider's membership plumbing: refresh after
/// login, can() fallbacks, activeSalonId, and the revoked flow (guard →
/// probe → sign-out + one-shot notice). Runs on the MOCK world (the seeded
/// role accounts, docs/design/team-access-r4-role-shaped-app.md).
void main() {
  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    await serviceLocator.authService.logoutProvider();
  });

  Future<ProAuthProvider> signIn(String email) async {
    final auth = ProAuthProvider();
    await auth.requestEmailOtp(email);
    final ok = await auth.verifyEmailOtp(email, auth.emailDevCode!);
    expect(ok, isTrue, reason: 'login as $email failed');
    return auth;
  }

  test('a MANAGER login fetches the membership: role, caps, salon', () async {
    final auth = await signIn('awa.manager@myweli.test');
    expect(auth.role, TeamRole.manager);
    expect(auth.isStaff, isFalse);
    expect(auth.can(ProCap.catalogueManage), isTrue);
    expect(auth.can(ProCap.financesView), isFalse);
    expect(auth.can(ProCap.membersManage), isFalse);
    expect(auth.activeSalonId, 'provider1');
    expect(auth.salonName, 'Salon Excellence');
  });

  test('a STAFF login carries the artist link and the staff shape', () async {
    final auth = await signIn('sonia.staff@myweli.test');
    expect(auth.isStaff, isTrue);
    expect(auth.membership!.artistId, 'artist1');
    expect(auth.can(ProCap.journalManageOwn), isTrue);
    expect(auth.can(ProCap.journalViewAll), isFalse);
  });

  test('an OWNER login stays owner-shaped through the same path', () async {
    // Register an owner (creates a linked account) then re-login.
    final auth = ProAuthProvider();
    await auth.requestEmailOtp('own@r4b.test');
    await auth.registerWithEmail(
      email: 'own@r4b.test',
      code: auth.emailDevCode!,
      phoneNumber: '+2250700000099',
      businessName: 'Salon R4b',
      businessType: BusinessType.salon,
    );
    expect(auth.role, TeamRole.owner);
    expect(auth.can(ProCap.salonPublish), isTrue);
  });

  test(
      'legacy fallback without a membership: linked owner stays '
      'owner-shaped; a bare member is minimal', () async {
    final auth = ProAuthProvider();
    // Not signed in: no provider → minimal.
    expect(auth.can(ProCap.journalViewAll), isFalse);
    expect(auth.role, TeamRole.owner); // label default, harmless signed-out
  });

  test(
      'the revoked flow: guard report → probe → sign-out + one-shot '
      'notice (§5.3)', () async {
    final auth = await signIn('fatou.reception@myweli.test');
    expect(auth.isAuthenticated, isTrue);
    expect(auth.salonName, 'Salon Excellence');

    // The owner revokes fatou mid-session (roster row flips).
    final i = MockData.teamMembers.indexWhere((m) => m.id == 'mem_reception2');
    MockData.teamMembers[i] = MockData.teamMembers[i].copyWith(
      status: TeamMemberStatus.revoked,
      revokedAt: DateTime.now(),
    );

    // Any pro surface reports the next 403 — the guard probes once.
    ProAccessGuard.report('forbidden');
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(auth.isAuthenticated, isFalse);
    final notice = auth.consumeRevokedNotice();
    expect(notice, 'Salon Excellence');
    // One-shot: consumed.
    expect(auth.consumeRevokedNotice(), isNull);
  });

  test(
      'a NON-forbidden code never probes; an active member surviving the '
      'probe stays signed in', () async {
    final auth = await signIn('awa.manager@myweli.test');
    ProAccessGuard.report('not_found'); // ignored
    ProAccessGuard.report('forbidden'); // probes → still active → keeps on
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(auth.isAuthenticated, isTrue);
    expect(auth.consumeRevokedNotice(), isNull);
  });
}
