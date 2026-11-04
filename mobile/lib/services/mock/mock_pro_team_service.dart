import '../../core/constants/app_constants.dart';
import '../../core/di/dependency_injection.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/salon_id.dart';
import '../../core/utils/team_error_messages.dart';
import '../../models/api_response.dart';
import '../../models/team_invitation.dart';
import '../../models/team_member.dart';
import '../interfaces/pro_team_service_interface.dart';
import '../interfaces/subscription_service_interface.dart';
import 'mock_data.dart';
import 'mock_ids.dart';
import 'mock_session.dart';

/// The server's daily invitation caps (T37, `kDefaultInviteLimits` in
/// backend/lib/src/security/identity_limits.dart): per salon, then per salon
/// and address.
const ({int perSalon, int perAddress}) kMockInviteLimits = (
  perSalon: 20,
  perAddress: 3,
);

/// The mailbox behind an address, the server's way
/// (`canonicalInviteAddress`): a `+tag` dropped, and Gmail's dots and
/// `googlemail.com` folded — so the aliases of one person share a bucket.
String _canonicalAddress(String emailKey) {
  final at = emailKey.lastIndexOf('@');
  if (at <= 0) return emailKey;
  var local = emailKey.substring(0, at);
  var domain = emailKey.substring(at + 1);
  final plus = local.indexOf('+');
  if (plus > 0) local = local.substring(0, plus);
  if (domain == 'gmail.com' || domain == 'googlemail.com') {
    local = local.replaceAll('.', '');
    domain = 'gmail.com';
  }
  return '$local@$domain';
}

/// Demo team service over `MockData.teamMembers`/`teamInvitations`. The
/// acting salon derives from the session — the R6 selection first, then the
/// account's linked salon (default `provider1`, the seeded owner), so the
/// roster/gates follow the « Mes salons » switcher. Enforces EVERY server
/// gate with the SAME machine codes so screens are built against the real
/// contract. The invitee side is keyed, as on the server, by the SIGNED-IN
/// account's email — [invitationEmail] stands in when there is no session
/// (isolated tests, signed-out demos).
class MockProTeamService implements ProTeamServiceInterface {
  MockProTeamService({
    this._subscriptions,
    this.invitationEmail = 'invitee@myweli.test',
  });

  /// When provided, invite gates on the mock offer state (offer_required /
  /// seat_limit) exactly like the backend; absent → gates pass.
  final SubscriptionServiceInterface? _subscriptions;

  /// The email the invitee methods act for when no account is signed in.
  String invitationEmail;

  /// The invitee: the session's account — what GET /me/provider/invitations
  /// keys on (docs/design/pro-rejoin-gate.md §5) — else [invitationEmail].
  Future<({String email, String? accountId})> _invitee() async {
    try {
      final account = await serviceLocator.authService.getCurrentProvider();
      final email = account?.email;
      if (email != null && email.isNotEmpty) {
        return (email: email.trim().toLowerCase(), accountId: account!.id);
      }
    } catch (_) {
      /* locator not wired (isolated tests) → the stand-in */
    }
    return (email: invitationEmail.toLowerCase(), accountId: null);
  }

  /// The acting salon — the same rule as ProAuthProvider.activeSalonId
  /// (selection → the account's own salon → the membership's), else the
  /// seeded salon (docs/design/services-acting-salon.md).
  Future<SalonId> _providerId() => mockActingSalonId();

  /// One attempt into a daily bucket, counted the server's way
  /// (`InMemoryRateLimiter.hit`): every attempt that reaches the bucket
  /// counts, a refused one included; the window is the UTC day on
  /// [AppClock].
  bool _hit(String bucket, int limit) {
    final day =
        AppClock.now().toUtc().millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final key = '$day|$bucket';
    final count = (MockData.inviteBuckets[key] ?? 0) + 1;
    MockData.inviteBuckets[key] = count;
    return count <= limit;
  }

  /// The member's row in the acting salon, or -1: the server guards every
  /// member write to the path salon (`_guardMember`, → `not_found`). It
  /// searched every salon's roster.
  Future<int> _rowAt(String memberId) async {
    final providerId = await _providerId();
    return MockData.teamMembers.indexWhere(
      (m) => m.id == memberId && m.providerId == providerId,
    );
  }

  ApiResponse<T> _fail<T>(String code) =>
      ApiResponse.error(teamErrorMessage(code), code: code);

  @override
  Future<ApiResponse<List<TeamMember>>> getMembers() async {
    await Future.delayed(AppConstants.mockDelay);
    final providerId = await _providerId();
    final rows =
        MockData.teamMembers.where((m) => m.providerId == providerId).toList()
          ..sort((a, b) {
            if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
            return a.invitedAt.compareTo(b.invitedAt);
          });
    return ApiResponse.success(rows);
  }

  @override
  Future<ApiResponse<TeamMember>> inviteMember({
    required String email,
    required TeamRole role,
    String? artistId,
    String? idempotencyKey,
  }) async {
    // The mock never loses an answer, so it never sees a retry under the
    // same key: the key is accepted and has nothing to do here.
    await Future.delayed(AppConstants.mockDelay);
    final key = email.trim().toLowerCase();
    if (key.isEmpty || !key.contains('@')) {
      return ApiResponse.error(
        'Adresse e-mail invalide.',
        code: 'invalid_input',
      );
    }
    if (role == TeamRole.owner) return _fail('invalid_role');

    String? artistName;
    if (role == TeamRole.staff) {
      if (artistId == null || artistId.isEmpty) {
        return _fail('artist_required');
      }
      artistName = await _artistName(artistId);
      if (artistName == null) return _fail('artist_not_found');
    }

    final providerId = await _providerId();
    // One row per (salon, address), as on the server (UNIQUE (provider_id,
    // email)): an owner's row, an active member or a still-valid invitation
    // holds the address; a revoked row or an expired invitation is invited
    // again ON THE SAME ROW (docs/design/backend-team-reinvite.md).
    final at = MockData.teamMembers.indexWhere(
      (m) => m.providerId == providerId && m.email == key,
    );
    final current = at == -1 ? null : MockData.teamMembers[at];
    if (current != null &&
        (current.isOwner ||
            current.status == TeamMemberStatus.active ||
            (current.isPending && !current.expired))) {
      return _fail('member_exists');
    }

    // The R2a gates: a live offer + a free seat (per salon — R6).
    final subs = _subscriptions;
    if (subs != null) {
      final state = await subs.getSalonSubscription(providerId);
      if (!state.success || !(state.data?.isLive ?? false)) {
        return _fail('offer_required');
      }
      final seats = state.data!.seats;
      if (seats.used >= seats.cap) return _fail('seat_limit');
    }

    // T37, after every gate above (an honest refusal costs nothing): the
    // salon's bucket, then the (salon, address) one — a salon refused at its
    // own writes nothing to the address's. It was one counter per instance,
    // for every salon and address, that never started a new day.
    if (!_hit('salon:$providerId', kMockInviteLimits.perSalon) ||
        !_hit(
          'addr:$providerId:${_canonicalAddress(key)}',
          kMockInviteLimits.perAddress,
        )) {
      return _fail('invite_rate_limited');
    }

    final salonName =
        MockData.providers.where((p) => p.id == providerId).firstOrNull?.name ??
        'Salon Excellence';
    final member = TeamMember(
      id: current?.id ?? MockIds.next('mem'),
      providerId: providerId,
      email: key,
      role: role,
      status: TeamMemberStatus.invited,
      invitedAt: AppClock.now(),
      accountId: current?.accountId,
      artistId: role == TeamRole.staff ? artistId : null,
      artistName: artistName,
      expiresAt: AppClock.now().add(const Duration(days: 7)),
      resendsLeft: 3,
    );
    if (current != null) {
      MockData.teamMembers[at] = member;
      _removeInvitationCard(current);
    } else {
      MockData.teamMembers.add(member);
    }
    (MockData.teamInvitations[key] ??= []).add(
      TeamInvitation(
        id: member.id,
        providerId: providerId,
        salonName: salonName,
        role: role,
        roleLabel: teamRoleLabel(role),
        expiresAt: member.expiresAt,
      ),
    );
    return ApiResponse.success(member, message: 'Invitation envoyée à $key');
  }

  @override
  Future<ApiResponse<TeamMember>> changeRole(
    String memberId, {
    required TeamRole role,
    String? artistId,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final i = await _rowAt(memberId);
    if (i == -1) return _fail('not_found');
    final member = MockData.teamMembers[i];
    if (member.isOwner) return _fail('owner_protected');
    // The server refuses a revoked member's role (409 member_revoked, B6.8c).
    if (member.status == TeamMemberStatus.revoked) {
      return _fail('member_revoked');
    }
    if (role == TeamRole.owner) return _fail('invalid_role');

    String? linkedArtist = member.artistId;
    String? linkedName = member.artistName;
    if (role == TeamRole.staff) {
      final candidate = (artistId != null && artistId.isNotEmpty)
          ? artistId
          : linkedArtist;
      if (candidate == null || candidate.isEmpty) {
        return _fail('artist_required');
      }
      final name = await _artistName(candidate);
      if (name == null) return _fail('artist_not_found');
      linkedArtist = candidate;
      linkedName = name;
    }
    final updated = member.copyWith(
      role: role,
      artistId: linkedArtist,
      artistName: linkedName,
    );
    MockData.teamMembers[i] = updated;
    return ApiResponse.success(updated);
  }

  @override
  Future<ApiResponse<TeamMember>> revokeMember(String memberId) async {
    await Future.delayed(AppConstants.mockDelay);
    final i = await _rowAt(memberId);
    if (i == -1) return _fail('not_found');
    final member = MockData.teamMembers[i];
    if (member.isOwner) return _fail('owner_protected');
    final updated = member.copyWith(
      status: TeamMemberStatus.revoked,
      revokedAt: AppClock.now(),
    );
    MockData.teamMembers[i] = updated;
    _removeInvitationCard(member);
    return ApiResponse.success(updated);
  }

  @override
  Future<ApiResponse<TeamMember>> resendInvitation(String memberId) async {
    await Future.delayed(AppConstants.mockDelay);
    final i = await _rowAt(memberId);
    if (i == -1) return _fail('not_found');
    final member = MockData.teamMembers[i];
    if (member.isOwner) return _fail('owner_protected');
    if (!member.isPending) {
      return ApiResponse.error(
        'Ce membre est déjà actif.',
        code: 'invalid_state',
      );
    }
    if (member.resendsLeft <= 0) {
      return ApiResponse.error(
        resendBudgetExhaustedMessage,
        code: 'invite_rate_limited',
      );
    }
    final updated = member.copyWith(
      expiresAt: AppClock.now().add(const Duration(days: 7)),
      resendsLeft: member.resendsLeft - 1,
      expired: false,
    );
    MockData.teamMembers[i] = updated;
    return ApiResponse.success(updated);
  }

  @override
  Future<ApiResponse<List<TeamInvitation>>> getMyInvitations() async {
    await Future.delayed(AppConstants.mockDelay);
    final invitee = await _invitee();
    final cards =
        MockData.teamInvitations[invitee.email] ?? const <TeamInvitation>[];
    final unexpired = cards
        .where(
          (c) => c.expiresAt == null || c.expiresAt!.isAfter(AppClock.now()),
        )
        .toList();
    return ApiResponse.success(unexpired);
  }

  @override
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId) async {
    await Future.delayed(AppConstants.mockDelay);
    final invitee = await _invitee();
    final key = invitee.email;
    final cards = MockData.teamInvitations[key] ?? const <TeamInvitation>[];
    final card = cards.where((c) => c.id == invitationId).firstOrNull;
    if (card == null) return _fail('not_found');
    if (card.expiresAt != null && card.expiresAt!.isBefore(AppClock.now())) {
      return _fail('invitation_expired');
    }
    MockData.teamInvitations[key]?.removeWhere((c) => c.id == invitationId);

    // The accepting account becomes the row's — a former member's row
    // already carries it (re-invitations keep account_id).
    final accountId = invitee.accountId ?? 'member_$key';
    final i = MockData.teamMembers.indexWhere((m) => m.id == invitationId);
    if (i != -1) {
      final activated = MockData.teamMembers[i].copyWith(
        status: TeamMemberStatus.active,
        accountId: MockData.teamMembers[i].accountId ?? accountId,
        acceptedAt: AppClock.now(),
      );
      MockData.teamMembers[i] = activated;
      return ApiResponse.success(activated);
    }
    // A card from another salon (roster not modeled) — synthesize the row.
    return ApiResponse.success(
      TeamMember(
        id: invitationId,
        providerId: card.providerId,
        email: key,
        role: card.role,
        status: TeamMemberStatus.active,
        invitedAt: AppClock.now(),
        accountId: accountId,
        acceptedAt: AppClock.now(),
      ),
    );
  }

  @override
  Future<ApiResponse<bool>> declineInvitation(String invitationId) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = (await _invitee()).email;
    final cards = MockData.teamInvitations[key];
    final exists = cards?.any((c) => c.id == invitationId) ?? false;
    if (!exists) return _fail('not_found');
    cards!.removeWhere((c) => c.id == invitationId);
    // As on the server: a fresh invitation disappears; a former member's
    // re-invitation (accountId kept) goes back to revoked — deleting it
    // would leave that account with no row (backend-team-reinvite.md).
    final i = MockData.teamMembers.indexWhere((m) => m.id == invitationId);
    if (i != -1) {
      final m = MockData.teamMembers[i];
      if (m.accountId == null) {
        MockData.teamMembers.removeAt(i);
      } else {
        MockData.teamMembers[i] = m.copyWith(
          status: TeamMemberStatus.revoked,
          revokedAt: AppClock.now(),
        );
      }
    }
    return ApiResponse.success(true);
  }

  /// Validates against the LIVE mock roster (MockData.providers artists —
  /// inline-created fiches land there via MockProArtistService._syncProvider).
  Future<String?> _artistName(String artistId) async {
    final providerId = await _providerId();
    for (final p in MockData.providers) {
      if (p.id != providerId) continue;
      for (final a in p.artists) {
        if (a.id == artistId) return a.name;
      }
    }
    for (final a in MockData.getArtistsForProvider(providerId)) {
      if (a.id == artistId) return a.name;
    }
    return null;
  }

  void _removeInvitationCard(TeamMember member) {
    MockData.teamInvitations[member.email]?.removeWhere(
      (c) => c.id == member.id,
    );
  }
}
