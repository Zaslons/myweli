import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/pro_membership.dart';
import 'package:myweli/models/provider_session.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/team_member.dart';

/// Team access R4b — the membership model: DTO parse, can(), the mock-only
/// preset mirror, and the session round-trip (incl. legacy pre-R4b JSON).
void main() {
  group('ProMembership', () {
    test('parses the /me/provider membership block (+ folded salon)', () {
      final m = ProMembership.fromJson(const {
        'role': 'staff',
        'capabilities': ['journal.manage.own', 'journal.view.own'],
        'artistId': 'a1',
        'artistName': 'Awa',
        'salonId': 'p1',
        'salonName': 'Salon Excellence',
      });
      expect(m.role, TeamRole.staff);
      expect(m.isStaff, isTrue);
      expect(m.can(ProCap.journalViewOwn), isTrue);
      expect(m.can(ProCap.journalViewAll), isFalse);
      expect(m.artistName, 'Awa');
      expect(m.salonName, 'Salon Excellence');
      expect(m.roleLabel, 'Collaborateur');
      // Round-trip.
      expect(ProMembership.fromJson(m.toJson()), m);
    });

    test('unknown role falls back to the MINIMAL staff shape', () {
      final m = ProMembership.fromJson(const {
        'role': 'superuser',
        'capabilities': <String>[],
        'salonId': 'p1',
        'salonName': 'X',
      });
      expect(m.role, TeamRole.staff);
      expect(m.can(ProCap.membersManage), isFalse);
    });

    test('the preset mirror matches the §2.2 matrix per role', () {
      final owner = presetCapabilitiesFor(TeamRole.owner);
      expect(owner, contains(ProCap.financesView));
      expect(owner, contains(ProCap.salonPublish));
      expect(owner, contains(ProCap.membersManage));

      final manager = presetCapabilitiesFor(TeamRole.manager);
      expect(manager, contains(ProCap.catalogueManage));
      expect(manager, contains(ProCap.journalManageAll));
      expect(manager, isNot(contains(ProCap.financesView)));
      expect(manager, isNot(contains(ProCap.membersManage)));
      expect(manager, isNot(contains(ProCap.subscriptionManage)));

      final reception = presetCapabilitiesFor(TeamRole.reception);
      expect(reception, contains(ProCap.journalManageAll));
      expect(reception, contains(ProCap.clientsView));
      expect(reception, isNot(contains(ProCap.catalogueManage)));
      expect(reception, isNot(contains(ProCap.availabilityManage)));

      expect(
        presetCapabilitiesFor(TeamRole.staff),
        {ProCap.journalViewOwn, ProCap.journalManageOwn},
      );
    });
  });

  group('ProviderSession + membership', () {
    final user = ProviderUser(
      id: 'acc1',
      phoneNumber: '',
      businessName: '',
      businessType: BusinessType.other,
      email: 'sonia@x.test',
      createdAt: DateTime(2026),
    );

    test('round-trips the cached membership', () {
      final session = ProviderSession(
        token: 't',
        refreshToken: 'r',
        provider: user,
        membership: const ProMembership(
          role: TeamRole.reception,
          capabilities: {ProCap.journalViewAll, ProCap.clientsView},
          salonId: 'p1',
          salonName: 'Salon Excellence',
        ),
      );
      final back = ProviderSession.fromJson(session.toJson());
      expect(back.membership!.role, TeamRole.reception);
      expect(back.membership!.can(ProCap.clientsView), isTrue);
      expect(back.membership!.salonName, 'Salon Excellence');
    });

    test('LEGACY pre-R4b JSON (no membership key) still parses', () {
      final legacy = {
        'token': 't',
        'refreshToken': 'r',
        'provider': user.toJson(),
      };
      final session = ProviderSession.fromJson(legacy);
      expect(session.membership, isNull);
      expect(session.provider.email, 'sonia@x.test');
    });
  });
}
