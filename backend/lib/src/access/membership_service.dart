import '../auth/provider_auth_repository.dart';
import 'capabilities.dart';
import 'membership_repository.dart';

/// Module `access` §4: per-request authorization over memberships. NEVER
/// cached across requests — firing someone is effective on their very next
/// call (threat T38). Deny by default. Design: docs/modules/access.md.
class MembershipService {
  MembershipService(this._members, this._providerAuth);

  final MembershipRepository _members;
  final ProviderAuthRepository _providerAuth;

  /// Does [accountId] hold [capability] inside [providerId]?
  /// `status != active` → false (revoked/invited members are outsiders).
  Future<bool> can(
    String accountId,
    String providerId,
    String capability,
  ) async {
    final member = await memberOf(accountId, providerId);
    if (member == null) return false;
    return capabilitiesFor(member.role).contains(capability);
  }

  /// The ACTIVE member row of [accountId] inside [providerId], with a legacy
  /// self-heal: a linked owner account (provider_users.provider_id) that
  /// predates the membership table gets its owner row on first touch — the
  /// runtime mirror of the 0027 backfill (also covers in-memory mode).
  Future<Member?> memberOf(String accountId, String providerId) async {
    final member = await _members.activeMember(accountId, providerId);
    if (member != null) return member;
    final account = await _providerAuth.accountById(accountId);
    if (account == null || account.providerId != providerId) return null;
    return _members.ensureOwner(
      providerId: providerId,
      accountId: accountId,
      email: account.email ?? account.phoneNumber,
    );
  }

  /// T40 (module `access` R4a): how far into [providerId]'s journal
  /// [accountId] reaches. `(all: true)` → the whole salon;
  /// `(all: false, ownArtistId: X)` → that artist's column only; both empty
  /// → forbidden. A staff member with a NULL artistId gets NOTHING — deny
  /// by default (a mislinked Collaborateur must never see a partial day).
  Future<({bool all, String? ownArtistId})> journalScope(
    String accountId,
    String providerId, {
    required bool manage,
  }) async {
    final member = await memberOf(accountId, providerId);
    if (member == null) return (all: false, ownArtistId: null);
    final caps = capabilitiesFor(member.role);
    if (caps.contains(manage ? Cap.journalManageAll : Cap.journalViewAll)) {
      return (all: true, ownArtistId: null);
    }
    if (caps.contains(manage ? Cap.journalManageOwn : Cap.journalViewOwn)) {
      return (all: false, ownArtistId: member.artistId);
    }
    return (all: false, ownArtistId: null);
  }

  /// The NO-SELECTION fallback: the account's linked salon (owner) or its
  /// first active membership (member, R2+). Null for outsiders. R6: explicit
  /// selection goes through [salonForRequest]; this stays the default so
  /// pre-R6 clients keep working unchanged.
  Future<String?> activeSalonFor(String accountId) async {
    final account = await _providerAuth.accountById(accountId);
    if (account?.providerId != null) return account!.providerId;
    return (await _members.firstActiveForAccount(accountId))?.providerId;
  }

  /// R6: the acting salon for THIS request. An explicit [salonId] must match
  /// an ACTIVE membership ([memberOf] — incl. the legacy linked-owner
  /// self-heal); no match → null, and the route answers a uniform 403
  /// `forbidden` — never-member, revoked-there and nonexistent salons are
  /// indistinguishable (no membership-existence oracle, threat T55).
  /// Explicit selection never auto-provisions. Absent/empty → the legacy
  /// [activeSalonFor] fallback.
  Future<String?> salonForRequest(String accountId, {String? salonId}) async {
    if (salonId != null && salonId.isNotEmpty) {
      return await memberOf(accountId, salonId) == null ? null : salonId;
    }
    return activeSalonFor(accountId);
  }

  /// Does the account hold ANY membership row (any status)? The provisioning
  /// guard's question: invited/active members must never get a salon
  /// auto-created (module doc §2.3-1).
  Future<bool> hasAnyMembership(String accountId) async =>
      (await _members.listForAccount(accountId)).isNotEmpty;
}
