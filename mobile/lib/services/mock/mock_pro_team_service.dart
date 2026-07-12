import '../../core/constants/app_constants.dart';
import '../../core/utils/team_error_messages.dart';
import '../../models/api_response.dart';
import '../../models/team_invitation.dart';
import '../../models/team_member.dart';
import '../interfaces/pro_team_service_interface.dart';
import '../interfaces/subscription_service_interface.dart';
import 'mock_data.dart';

/// Demo team service over `MockData.teamMembers`/`teamInvitations`
/// (salon context: `provider1`, the seeded owner). Enforces EVERY server
/// gate with the SAME machine codes so screens are built against the real
/// contract. The invitee side is keyed by [invitationEmail] — the mock's
/// stand-in for the session's account email.
class MockProTeamService implements ProTeamServiceInterface {
  MockProTeamService({
    SubscriptionServiceInterface? subscriptions,
    this.invitationEmail = 'invitee@myweli.test',
    this.maxInvitesPerDay = 20,
  }) : _subscriptions = subscriptions;

  /// When provided, invite gates on the mock offer state (offer_required /
  /// seat_limit) exactly like the backend; absent → gates pass.
  final SubscriptionServiceInterface? _subscriptions;

  /// The email the invitee methods act for (mock session identity).
  String invitationEmail;

  final int maxInvitesPerDay;
  int _invitesToday = 0;

  static const _providerId = 'provider1';

  ApiResponse<T> _fail<T>(String code) =>
      ApiResponse.error(teamErrorMessage(code), code: code);

  @override
  Future<ApiResponse<List<TeamMember>>> getMembers() async {
    await Future.delayed(AppConstants.mockDelay);
    final rows = List<TeamMember>.from(MockData.teamMembers)
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
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = email.trim().toLowerCase();
    if (key.isEmpty || !key.contains('@')) {
      return ApiResponse.error('Adresse e-mail invalide.',
          code: 'invalid_input');
    }
    if (role == TeamRole.owner) return _fail('invalid_role');

    String? artistName;
    if (role == TeamRole.staff) {
      if (artistId == null || artistId.isEmpty) {
        return _fail('artist_required');
      }
      artistName = _artistName(artistId);
      if (artistName == null) return _fail('artist_not_found');
    }

    final duplicate = MockData.teamMembers.any((m) =>
        m.email == key &&
        (m.status == TeamMemberStatus.active || (m.isPending && !m.expired)));
    if (duplicate) return _fail('member_exists');

    // The R2a gates: a live offer + a free seat.
    final subs = _subscriptions;
    if (subs != null) {
      final state = await subs.getSalonSubscription(_providerId);
      if (!state.success || !(state.data?.isLive ?? false)) {
        return _fail('offer_required');
      }
      final seats = state.data!.seats;
      if (seats.used >= seats.cap) return _fail('seat_limit');
    }

    if (_invitesToday >= maxInvitesPerDay) return _fail('invite_rate_limited');
    _invitesToday++;

    final member = TeamMember(
      id: 'mem_${DateTime.now().millisecondsSinceEpoch}',
      providerId: _providerId,
      email: key,
      role: role,
      status: TeamMemberStatus.invited,
      invitedAt: DateTime.now(),
      artistId: role == TeamRole.staff ? artistId : null,
      artistName: artistName,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      resendsLeft: 3,
    );
    MockData.teamMembers.add(member);
    (MockData.teamInvitations[key] ??= []).add(TeamInvitation(
      id: member.id,
      providerId: _providerId,
      salonName: 'Salon Excellence',
      role: role,
      roleLabel: teamRoleLabel(role),
      expiresAt: member.expiresAt,
    ));
    return ApiResponse.success(member, message: 'Invitation envoyée à $key');
  }

  @override
  Future<ApiResponse<TeamMember>> changeRole(
    String memberId, {
    required TeamRole role,
    String? artistId,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final i = MockData.teamMembers.indexWhere((m) => m.id == memberId);
    if (i == -1) return _fail('not_found');
    final member = MockData.teamMembers[i];
    if (member.isOwner) return _fail('owner_protected');
    if (role == TeamRole.owner) return _fail('invalid_role');

    String? linkedArtist = member.artistId;
    String? linkedName = member.artistName;
    if (role == TeamRole.staff) {
      final candidate =
          (artistId != null && artistId.isNotEmpty) ? artistId : linkedArtist;
      if (candidate == null || candidate.isEmpty) {
        return _fail('artist_required');
      }
      final name = _artistName(candidate);
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
    final i = MockData.teamMembers.indexWhere((m) => m.id == memberId);
    if (i == -1) return _fail('not_found');
    final member = MockData.teamMembers[i];
    if (member.isOwner) return _fail('owner_protected');
    final updated = member.copyWith(
      status: TeamMemberStatus.revoked,
      revokedAt: DateTime.now(),
    );
    MockData.teamMembers[i] = updated;
    _removeInvitationCard(member);
    return ApiResponse.success(updated);
  }

  @override
  Future<ApiResponse<TeamMember>> resendInvitation(String memberId) async {
    await Future.delayed(AppConstants.mockDelay);
    final i = MockData.teamMembers.indexWhere((m) => m.id == memberId);
    if (i == -1) return _fail('not_found');
    final member = MockData.teamMembers[i];
    if (member.isOwner) return _fail('owner_protected');
    if (!member.isPending) {
      return ApiResponse.error('Ce membre est déjà actif.',
          code: 'invalid_state');
    }
    if (member.resendsLeft <= 0) {
      return ApiResponse.error(resendBudgetExhaustedMessage,
          code: 'invite_rate_limited');
    }
    final updated = member.copyWith(
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      resendsLeft: member.resendsLeft - 1,
      expired: false,
    );
    MockData.teamMembers[i] = updated;
    return ApiResponse.success(updated);
  }

  @override
  Future<ApiResponse<List<TeamInvitation>>> getMyInvitations() async {
    await Future.delayed(AppConstants.mockDelay);
    final cards = MockData.teamInvitations[invitationEmail.toLowerCase()] ??
        const <TeamInvitation>[];
    final unexpired = cards
        .where(
            (c) => c.expiresAt == null || c.expiresAt!.isAfter(DateTime.now()))
        .toList();
    return ApiResponse.success(unexpired);
  }

  @override
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = invitationEmail.toLowerCase();
    final cards = MockData.teamInvitations[key] ?? const <TeamInvitation>[];
    final card = cards.where((c) => c.id == invitationId).firstOrNull;
    if (card == null) return _fail('not_found');
    if (card.expiresAt != null && card.expiresAt!.isBefore(DateTime.now())) {
      return _fail('invitation_expired');
    }
    MockData.teamInvitations[key]?.removeWhere((c) => c.id == invitationId);

    final i = MockData.teamMembers.indexWhere((m) => m.id == invitationId);
    if (i != -1) {
      final activated = MockData.teamMembers[i].copyWith(
        status: TeamMemberStatus.active,
        accountId: 'member_$key',
        acceptedAt: DateTime.now(),
      );
      MockData.teamMembers[i] = activated;
      return ApiResponse.success(activated);
    }
    // A card from another salon (roster not modeled) — synthesize the row.
    return ApiResponse.success(TeamMember(
      id: invitationId,
      providerId: card.providerId,
      email: key,
      role: card.role,
      status: TeamMemberStatus.active,
      invitedAt: DateTime.now(),
      accountId: 'member_$key',
      acceptedAt: DateTime.now(),
    ));
  }

  @override
  Future<ApiResponse<bool>> declineInvitation(String invitationId) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = invitationEmail.toLowerCase();
    final cards = MockData.teamInvitations[key];
    final exists = cards?.any((c) => c.id == invitationId) ?? false;
    if (!exists) return _fail('not_found');
    cards!.removeWhere((c) => c.id == invitationId);
    MockData.teamMembers.removeWhere((m) => m.id == invitationId);
    return ApiResponse.success(true);
  }

  /// Validates against the LIVE mock roster (MockData.providers artists —
  /// inline-created fiches land there via MockProArtistService._syncProvider).
  String? _artistName(String artistId) {
    for (final p in MockData.providers) {
      if (p.id != _providerId) continue;
      for (final a in p.artists) {
        if (a.id == artistId) return a.name;
      }
    }
    for (final a in MockData.getArtistsForProvider(_providerId)) {
      if (a.id == artistId) return a.name;
    }
    return null;
  }

  void _removeInvitationCard(TeamMember member) {
    MockData.teamInvitations[member.email]
        ?.removeWhere((c) => c.id == member.id);
  }
}
