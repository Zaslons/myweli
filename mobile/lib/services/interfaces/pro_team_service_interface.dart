import '../../models/api_response.dart';
import '../../models/team_invitation.dart';
import '../../models/team_member.dart';

/// The salon team & invitations surface (module `access` R3 — consumes the
/// R2b API). Owner-only server-side (`members.manage`); the salon resolves
/// from the CALLER's session, never a client id. The invitee methods
/// (`getMyInvitations`/`acceptInvitation`/`declineInvitation`) work for any
/// pro identity. Design: docs/design/team-access-r3-app.md.
abstract class ProTeamServiceInterface {
  /// The roster — owner first, pending invitations included.
  Future<ApiResponse<List<TeamMember>>> getMembers();

  /// Invite by email. Errors: `member_exists`, `invalid_role`,
  /// `artist_required`/`artist_not_found` (Collaborateur ⇒ fiche),
  /// `offer_required`, `seat_limit`, `invite_rate_limited`.
  Future<ApiResponse<TeamMember>> inviteMember({
    required String email,
    required TeamRole role,
    String? artistId,
  });

  /// Change a member's role. The owner row → `owner_protected`.
  Future<ApiResponse<TeamMember>> changeRole(
    String memberId, {
    required TeamRole role,
    String? artistId,
  });

  /// Revoke access (idempotent; effective on the member's next request).
  Future<ApiResponse<TeamMember>> revokeMember(String memberId);

  /// Re-send a pending invitation (budget of 3 → `invite_rate_limited`).
  Future<ApiResponse<TeamMember>> resendInvitation(String memberId);

  /// The signed-in identity's pending invitations (account-email keyed).
  Future<ApiResponse<List<TeamInvitation>>> getMyInvitations();

  /// Accept under the CURRENT session (email must match; expired →
  /// `invitation_expired`).
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId);

  Future<ApiResponse<bool>> declineInvitation(String invitationId);
}
