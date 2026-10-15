import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/services/interfaces/pro_team_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';

/// The roster moves a rejoin-gate test needs (docs/design/pro-rejoin-gate.md),
/// on the mock world — shared by the unit, widget and golden tests so each
/// one says « revoked, then invited again » the same way the server does it.

/// The owner revokes [memberId]: the roster row flips, its account kept.
void revokeMember(String memberId) {
  final i = MockData.teamMembers.indexWhere((m) => m.id == memberId);
  MockData.teamMembers[i] = MockData.teamMembers[i].copyWith(
    status: TeamMemberStatus.revoked,
    revokedAt: AppClock.now(),
  );
}

/// The row accepted from anywhere — another device, the web: active again,
/// its card gone.
void activateMember(String memberId) {
  final i = MockData.teamMembers.indexWhere((m) => m.id == memberId);
  final row = MockData.teamMembers[i];
  MockData.teamMembers[i] = row.copyWith(
    status: TeamMemberStatus.active,
    acceptedAt: AppClock.now(),
  );
  MockData.teamInvitations[row.email]?.removeWhere((c) => c.id == memberId);
}

/// The acting salon invites [email] again through the mock's own invite —
/// for a revoked member that is the SAME row, revived (#596).
Future<void> reinvite(
  ProTeamServiceInterface team, {
  String email = kFatou,
  TeamRole role = TeamRole.reception,
  String? artistId,
}) async {
  final res = await team.inviteMember(
    email: email,
    role: role,
    artistId: artistId,
  );
  expect(res.success, isTrue, reason: 're-invite refused: ${res.code}');
}

/// A second salon invites [email] too — Beauté Divine, as Manager.
void inviteFromBeauteDivine({String email = kFatou}) {
  MockData.teamMembers.add(
    TeamMember(
      id: 'mem_p2_second',
      providerId: 'provider2',
      email: email,
      role: TeamRole.manager,
      status: TeamMemberStatus.invited,
      invitedAt: AppClock.now(),
      expiresAt: AppClock.now().add(const Duration(days: 5)),
      resendsLeft: 3,
    ),
  );
  (MockData.teamInvitations[email] ??= []).add(
    TeamInvitation(
      id: 'mem_p2_second',
      providerId: 'provider2',
      salonName: 'Beauté Divine',
      role: TeamRole.manager,
      roleLabel: 'Manager',
      expiresAt: AppClock.now().add(const Duration(days: 5)),
    ),
  );
}

/// Every card of [email] runs out — while the person is looking at it.
void expireInvitations({String email = kFatou}) {
  final cards = MockData.teamInvitations[email] ?? [];
  final past = AppClock.now().subtract(const Duration(days: 1));
  for (var i = 0; i < cards.length; i++) {
    final c = cards[i];
    cards[i] = TeamInvitation(
      id: c.id,
      providerId: c.providerId,
      salonName: c.salonName,
      role: c.role,
      roleLabel: c.roleLabel,
      expiresAt: past,
    );
  }
}

/// Fatou — Salon Excellence's seeded réception member (`mem_reception2`).
const kFatou = 'fatou.reception@myweli.test';
const kFatouRow = 'mem_reception2';

/// A bare account at [email] whose only membership was revoked, with no
/// card: the social sign-ins' identities, made into former members.
void bareRevokedAccount(String email) {
  MockData.providerUsers.removeWhere((p) => p.email == email);
  MockData.providerUsers.add(
    ProviderUser(
      id: 'member_social',
      phoneNumber: '',
      businessName: '',
      businessType: BusinessType.other,
      email: email,
      createdAt: DateTime.utc(2026, 6, 1),
    ),
  );
  MockData.teamMembers.add(
    TeamMember(
      id: 'mem_social',
      providerId: 'provider1',
      email: email,
      role: TeamRole.reception,
      status: TeamMemberStatus.revoked,
      invitedAt: DateTime.utc(2026, 6, 1),
      accountId: 'member_social',
      acceptedAt: DateTime.utc(2026, 6, 2),
      revokedAt: DateTime.utc(2026, 7, 1),
    ),
  );
  MockData.teamInvitations.remove(email);
}
