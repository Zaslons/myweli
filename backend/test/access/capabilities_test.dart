import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:test/test.dart';

/// The preset matrix must equal docs/modules/access.md §2.2 EXACTLY — this
/// test is the executable copy of that table.
void main() {
  test('the four presets match the §2.2 matrix exactly', () {
    expect(rolePresets.keys.toSet(), MemberRole.all);

    expect(rolePresets[MemberRole.owner], {
      Cap.journalViewAll,
      Cap.journalManageAll,
      Cap.journalViewOwn,
      Cap.journalManageOwn,
      Cap.clientsView,
      Cap.catalogueManage,
      Cap.availabilityManage,
      Cap.profileManage,
      Cap.financesView,
      Cap.depositManage,
      Cap.membersManage,
      Cap.subscriptionManage,
      Cap.salonPublish,
    });

    expect(rolePresets[MemberRole.manager], {
      Cap.journalViewAll,
      Cap.journalManageAll,
      Cap.journalViewOwn,
      Cap.journalManageOwn,
      Cap.clientsView,
      Cap.catalogueManage,
      Cap.availabilityManage,
      Cap.profileManage,
    });

    // Réception (sign-off 2026-07-11): the whole journal + the client base,
    // nothing else.
    expect(rolePresets[MemberRole.reception], {
      Cap.journalViewAll,
      Cap.journalManageAll,
      Cap.journalViewOwn,
      Cap.journalManageOwn,
      Cap.clientsView,
    });

    // Collaborateur: « ma journée » only.
    expect(rolePresets[MemberRole.staff], {
      Cap.journalViewOwn,
      Cap.journalManageOwn,
    });
  });

  test('money, team, billing and go-live are owner-only', () {
    for (final role in [
      MemberRole.manager,
      MemberRole.reception,
      MemberRole.staff,
    ]) {
      final caps = capabilitiesFor(role);
      expect(caps.contains(Cap.financesView), isFalse, reason: role);
      expect(caps.contains(Cap.depositManage), isFalse, reason: role);
      expect(caps.contains(Cap.membersManage), isFalse, reason: role);
      expect(caps.contains(Cap.subscriptionManage), isFalse, reason: role);
      expect(caps.contains(Cap.salonPublish), isFalse, reason: role);
    }
  });

  test('unknown roles resolve to NO capabilities (deny by default)', () {
    expect(capabilitiesFor('superadmin'), isEmpty);
    expect(capabilitiesFor(''), isEmpty);
  });
}
