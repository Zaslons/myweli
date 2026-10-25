import '../../core/di/dependency_injection.dart';
import '../../core/utils/salon_id.dart';
import '../../models/pro_membership.dart';
import '../../models/provider_session.dart';
import '../../models/provider_user.dart';
import '../../models/team_member.dart';
import 'mock_data.dart';

/// The mock session as the server sees it: which salon it acts in, and what
/// it may do there. The team, catalogue and artist fakes all resolve through
/// here, so they cannot pick different salons (docs/design/hygiene-batch9.md
/// §2.5).
///
/// With no account — signed out, or the locator not wired (isolated tests) —
/// the fakes keep the owner-shaped world they always gave: the seeded owner,
/// acting in `provider1`.

Future<ProviderUser?> _account() async {
  try {
    return await serviceLocator.authService.getCurrentProvider();
  } catch (_) {
    return null; // locator not wired (isolated tests)
  }
}

/// The account's ACTIVE row in [salonId] (owner rows included), or null.
TeamMember? mockActiveRow(ProviderUser account, SalonId salonId) {
  final email = account.email?.toLowerCase();
  for (final m in MockData.teamMembers) {
    if (m.providerId != salonId || m.status != TeamMemberStatus.active) {
      continue;
    }
    if (m.accountId == account.id || (email != null && m.email == email)) {
      return m;
    }
  }
  return null;
}

/// The salon the session acts in — the path salon `ApiProService` sends with
/// a catalogue or artist write (`ProviderSession.actingSalonId`): the R6
/// selection, then the account's own salon, then its membership's
/// (docs/design/services-acting-salon.md). A session whose membership is not
/// cached yet takes the one `GET /me/provider` would give it: its first
/// active row.
Future<SalonId> mockActingSalonId() async {
  final account = await _account();
  if (account == null) return const SalonId('provider1');
  final auth = serviceLocator.authService;
  final acting = resolveActingSalonId(
    selected: await auth.getSelectedProviderSalon(),
    linked: account.providerId,
    membership: (await auth.getCachedProviderMembership())?.salonId,
  );
  if (acting != null) return acting;
  final email = account.email?.toLowerCase();
  for (final m in MockData.teamMembers) {
    if (m.status != TeamMemberStatus.active) continue;
    if (m.accountId == account.id || (email != null && m.email == email)) {
      return m.providerId;
    }
  }
  return const SalonId('provider1');
}

/// Whether the session holds [capability] in [salonId] — the server's tenant
/// check (`_members.can`, → `forbidden`): the account's own salon, or an
/// ACTIVE row there through its role's preset.
Future<bool> mockCan(SalonId salonId, String capability) async {
  final account = await _account();
  if (account == null) return true;
  if (account.providerId == salonId) return true;
  final row = mockActiveRow(account, salonId);
  return row != null && presetCapabilitiesFor(row.role).contains(capability);
}
