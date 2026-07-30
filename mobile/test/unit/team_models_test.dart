import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';

/// Team access R3 — the DTO-exact model parses (docs/design/
/// team-access-r3-app.md §4). SalonSubscription is covered in
/// subscription_test.dart.
void main() {
  group('TeamMember', () {
    test('parses a pending invitation row (full DTO)', () {
      final m = TeamMember.fromJson(const {
        'id': 'mem_1',
        'providerId': 'p1',
        'accountId': null,
        'email': 'ama@b.com',
        'role': 'staff',
        'artistId': 'a1',
        'artistName': 'Awa',
        'status': 'invited',
        'invitedAt': '2026-07-10T00:00:00.000Z',
        'acceptedAt': null,
        'revokedAt': null,
        'expiresAt': '2026-07-17T00:00:00.000Z',
        'resendsLeft': 2,
        'expired': false,
      });
      expect(m.role, TeamRole.staff);
      expect(m.status, TeamMemberStatus.invited);
      expect(m.isPending, isTrue);
      expect(m.isOwner, isFalse);
      expect(m.artistName, 'Awa');
      expect(m.resendsLeft, 2);
      expect(m.expired, isFalse);
      expect(m.roleLabel, 'Collaborateur');
      expect(m.toJson()['role'], 'staff');
    });

    test('unknown enums + missing optionals fall back safely', () {
      final m = TeamMember.fromJson(const {
        'id': 'mem_2',
        'email': 'x@b.com',
        'role': 'superadmin',
        'status': 'wat',
      });
      expect(m.role, TeamRole.staff); // safe fallback
      expect(m.status, TeamMemberStatus.revoked); // safe (inert) fallback
      expect(m.resendsLeft, 0);
      expect(m.expired, isFalse);
      expect(m.expiresAt, isNull);
    });

    test('the four French role labels', () {
      expect(teamRoleLabel(TeamRole.owner), 'Propriétaire');
      expect(teamRoleLabel(TeamRole.manager), 'Manager');
      expect(teamRoleLabel(TeamRole.reception), 'Réception');
      expect(teamRoleLabel(TeamRole.staff), 'Collaborateur');
    });
  });

  group('TeamInvitation', () {
    test('parses the invitee card', () {
      final i = TeamInvitation.fromJson(const {
        'id': 'mem_1',
        'providerId': 'p1',
        'salonName': 'Chez Awa',
        'role': 'reception',
        'roleLabel': 'Réception',
        'expiresAt': '2026-07-17T00:00:00.000Z',
      });
      expect(i.salonName, 'Chez Awa');
      expect(i.role, TeamRole.reception);
      expect(i.roleLabel, 'Réception');
      expect(i.expiresAt, isNotNull);
    });

    test('missing roleLabel derives from the role', () {
      final i = TeamInvitation.fromJson(const {
        'id': 'mem_1',
        'providerId': 'p1',
        'salonName': 'Chez Awa',
        'role': 'manager',
      });
      expect(i.roleLabel, 'Manager');
    });
  });
}
