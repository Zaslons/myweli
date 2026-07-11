import '../clients/provider_audit_log.dart';
import '../email/email_provider.dart';
import '../email/invitation_emails.dart';
import '../providers_repository.dart';
import '../subscription/salon_subscription_service.dart';
import '../validators.dart';
import 'capabilities.dart';
import 'membership_repository.dart';
import 'membership_service.dart';

typedef TeamResult = ({bool ok, String? error, Object? data});

/// Module `access` R2b (docs/design/team-access-r2b-invitations.md): the
/// invitation lifecycle + Équipe management. `MembershipService` stays the
/// hot-path resolver; this service owns the mutations — every one audited
/// (threat T36/T37), gated on the salon's offer and seats (R2a).
class TeamService {
  TeamService(
    this._members,
    this._resolver,
    this._providers,
    this._subscriptions,
    this._email,
    this._audit, {
    DateTime Function()? clock,
    int maxInvitesPerDay = 20,
  }) : _now = clock ?? (() => DateTime.now().toUtc()),
       _maxInvitesPerDay = maxInvitesPerDay;

  final MembershipRepository _members;
  final MembershipService _resolver;
  final ProvidersRepository _providers;
  final SalonSubscriptionService _subscriptions;
  final EmailProvider _email;
  final ProviderAuditLogRepository _audit;
  final DateTime Function() _now;
  final int _maxInvitesPerDay;

  static const invitationValidity = Duration(days: 7);
  static const _invitableRoles = {
    MemberRole.manager,
    MemberRole.reception,
    MemberRole.staff,
  };

  /// Per-(salon, day) invite counter (T37). Process-local, like
  /// LoginThrottle — move to a shared store if the API is ever scaled out.
  final Map<String, int> _inviteCounts = {};

  // ---- Équipe management (owner: members.manage) ---------------------------

  Future<TeamResult> list(String accountId, String providerId) async {
    if (!await _resolver.can(accountId, providerId, Cap.membersManage)) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final rows = await _members.listForProvider(providerId);
    final artistNames = await _artistNames(providerId);
    return (
      ok: true,
      error: null,
      data: {
        'items': [
          for (final m in rows)
            {
              ...m.toJson(),
              if (m.artistId != null) 'artistName': artistNames[m.artistId],
              'expired': m.isExpiredInvitation,
            },
        ],
      },
    );
  }

  Future<TeamResult> invite(
    String accountId,
    String providerId, {
    required Object? email,
    required Object? role,
    Object? artistId,
  }) async {
    if (!await _resolver.can(accountId, providerId, Cap.membersManage)) {
      return (ok: false, error: 'forbidden', data: null);
    }
    if (email is! String || !isValidEmail(email)) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final emailKey = email.toLowerCase();
    if (role is! String || !_invitableRoles.contains(role)) {
      return (ok: false, error: 'invalid_role', data: null);
    }
    String? linkedArtist;
    if (role == MemberRole.staff) {
      if (artistId is! String || artistId.isEmpty) {
        return (ok: false, error: 'artist_required', data: null);
      }
      final names = await _artistNames(providerId);
      if (!names.containsKey(artistId)) {
        return (ok: false, error: 'artist_not_found', data: null);
      }
      linkedArtist = artistId;
    }

    // Duplicate: an active or still-pending row for this (salon, email).
    final existing = await _members.listForProvider(providerId);
    for (final m in existing) {
      if (m.email == emailKey &&
          (m.status == 'active' ||
              (m.status == 'invited' && !m.isExpiredInvitation))) {
        return (ok: false, error: 'member_exists', data: null);
      }
    }

    // R2a gates: a live offer + a free seat (used counts active+invited).
    final state = await _subscriptions.stateFor(providerId);
    final status = state?['status'] as String?;
    if (state == null ||
        !(status == 'trial' || status == 'paid' || status == 'grace')) {
      return (ok: false, error: 'offer_required', data: null);
    }
    final seats = state['seats'] as Map<String, dynamic>;
    if ((seats['used'] as int) >= (seats['cap'] as int)) {
      return (ok: false, error: 'seat_limit', data: null);
    }

    // T37: per-salon/day budget.
    final dayKey = '$providerId/${_now().toIso8601String().substring(0, 10)}';
    final count = _inviteCounts[dayKey] ?? 0;
    if (count >= _maxInvitesPerDay) {
      return (ok: false, error: 'invite_rate_limited', data: null);
    }
    _inviteCounts[dayKey] = count + 1;

    final member = await _members.invite(
      providerId: providerId,
      email: emailKey,
      role: role,
      artistId: linkedArtist,
      invitedBy: accountId,
      expiresAt: _now().add(invitationValidity),
    );
    await _sendInvitationEmail(providerId, emailKey, role);
    await _audit.log(
      providerId: providerId,
      actorAccountId: accountId,
      action: 'members.invite',
      targetId: member.id,
      meta: {'role': role},
    );
    return (ok: true, error: null, data: member.toJson());
  }

  Future<TeamResult> changeRole(
    String accountId,
    String providerId,
    String memberId, {
    required Object? role,
    Object? artistId,
  }) async {
    final guard = await _guardMember(accountId, providerId, memberId);
    if (guard.error != null) return (ok: false, error: guard.error, data: null);
    if (role is! String || !_invitableRoles.contains(role)) {
      return (ok: false, error: 'invalid_role', data: null);
    }
    String? linkedArtist = guard.member!.artistId;
    if (role == MemberRole.staff) {
      final candidate = artistId is String && artistId.isNotEmpty
          ? artistId
          : linkedArtist;
      if (candidate == null || candidate.isEmpty) {
        return (ok: false, error: 'artist_required', data: null);
      }
      final names = await _artistNames(providerId);
      if (!names.containsKey(candidate)) {
        return (ok: false, error: 'artist_not_found', data: null);
      }
      linkedArtist = candidate;
    }
    final updated = await _members.updateMember(
      memberId,
      role: role,
      artistId: linkedArtist,
    );
    await _audit.log(
      providerId: providerId,
      actorAccountId: accountId,
      action: 'members.role_change',
      targetId: memberId,
      meta: {'role': role},
    );
    return (ok: true, error: null, data: updated?.toJson());
  }

  /// Idempotent; effective on the member's next request (T38 — the resolver
  /// never caches).
  Future<TeamResult> revoke(
    String accountId,
    String providerId,
    String memberId,
  ) async {
    final guard = await _guardMember(accountId, providerId, memberId);
    if (guard.error != null) return (ok: false, error: guard.error, data: null);
    final updated = await _members.revoke(memberId);
    await _audit.log(
      providerId: providerId,
      actorAccountId: accountId,
      action: 'members.revoke',
      targetId: memberId,
      meta: {},
    );
    return (ok: true, error: null, data: updated?.toJson());
  }

  Future<TeamResult> resend(
    String accountId,
    String providerId,
    String memberId,
  ) async {
    final guard = await _guardMember(accountId, providerId, memberId);
    if (guard.error != null) return (ok: false, error: guard.error, data: null);
    final member = guard.member!;
    if (member.status != 'invited') {
      return (ok: false, error: 'invalid_state', data: null);
    }
    final updated = await _members.resendInvite(
      memberId,
      _now().add(invitationValidity),
    );
    if (updated == null) {
      return (ok: false, error: 'invite_rate_limited', data: null);
    }
    await _sendInvitationEmail(providerId, member.email, member.role);
    await _audit.log(
      providerId: providerId,
      actorAccountId: accountId,
      action: 'members.resend',
      targetId: memberId,
      meta: {},
    );
    return (ok: true, error: null, data: updated.toJson());
  }

  // ---- The invitee side -----------------------------------------------------

  /// Invitation cards for a verified email (the login bridge + the authed
  /// list). Never reveals whether the email has an account (T37).
  Future<List<Map<String, dynamic>>> pendingInvitationsFor(String email) async {
    final rows = await _members.pendingByEmail(email);
    final cards = <Map<String, dynamic>>[];
    for (final m in rows) {
      final provider = await _providers.byId(m.providerId);
      cards.add({
        'id': m.id,
        'providerId': m.providerId,
        'salonName': (provider?['name'] as String?) ?? 'Salon',
        'role': m.role,
        'roleLabel': roleLabelFr(m.role),
        'expiresAt': m.expiresAt?.toIso8601String(),
      });
    }
    return cards;
  }

  /// Accept for a resolved ACCOUNT (the caller has proven the identity —
  /// session or login-grade proof). The account's verified email must match.
  Future<TeamResult> accept(
    String invitationId, {
    required String accountId,
    required String accountEmail,
  }) async {
    final member = await _members.byId(invitationId);
    if (member == null || member.status != 'invited') {
      return (ok: false, error: 'not_found', data: null);
    }
    if (member.email != accountEmail.toLowerCase()) {
      return (ok: false, error: 'forbidden', data: null);
    }
    if (member.isExpiredInvitation) {
      return (ok: false, error: 'invitation_expired', data: null);
    }
    final activated = await _members.activate(invitationId, accountId);
    await _audit.log(
      providerId: member.providerId,
      actorAccountId: accountId,
      action: 'members.accept',
      targetId: invitationId,
      meta: {'role': member.role},
    );
    return (ok: true, error: null, data: activated?.toJson());
  }

  /// Decline (email-proof): the row disappears; the owner can re-invite.
  Future<TeamResult> declineById(
    String invitationId, {
    required String email,
  }) async {
    final member = await _members.byId(invitationId);
    if (member == null || member.status != 'invited') {
      return (ok: false, error: 'not_found', data: null);
    }
    if (member.email != email.toLowerCase()) {
      return (ok: false, error: 'forbidden', data: null);
    }
    await _members.decline(invitationId);
    await _audit.log(
      providerId: member.providerId,
      actorAccountId: 'invitee',
      action: 'members.decline',
      targetId: invitationId,
      meta: {},
    );
    return (ok: true, error: null, data: null);
  }

  // ---- internals -------------------------------------------------------------

  /// Owner-protection + tenancy: the member must belong to [providerId], the
  /// caller must hold members.manage, and the OWNER row is immutable (T36).
  Future<({String? error, Member? member})> _guardMember(
    String accountId,
    String providerId,
    String memberId,
  ) async {
    if (!await _resolver.can(accountId, providerId, Cap.membersManage)) {
      return (error: 'forbidden', member: null);
    }
    final member = await _members.byId(memberId);
    if (member == null || member.providerId != providerId) {
      return (error: 'not_found', member: null);
    }
    if (member.role == MemberRole.owner) {
      return (error: 'owner_protected', member: null);
    }
    return (error: null, member: member);
  }

  Future<Map<String, String>> _artistNames(String providerId) async {
    final provider = await _providers.byId(providerId);
    final artists = (provider?['artists'] as List?) ?? const [];
    return {
      for (final a in artists.cast<Map<String, dynamic>>())
        if (a['id'] is String && a['name'] is String)
          a['id'] as String: a['name'] as String,
    };
  }

  Future<void> _sendInvitationEmail(
    String providerId,
    String email,
    String role,
  ) async {
    final provider = await _providers.byId(providerId);
    final salonName = (provider?['name'] as String?) ?? 'Un salon';
    await _email.send(
      to: email,
      subject: invitationEmailSubject(salonName),
      text: renderInvitationEmailText(salonName, role),
      html: renderInvitationEmailHtml(salonName, role),
    );
  }
}
