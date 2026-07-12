import 'provider_user.dart';
import 'team_invitation.dart';

/// How the invitee proves the invited email on the PUBLIC accept/decline
/// endpoints — the same identity the login attempt just verified (team
/// access R2b). Held in memory only, never persisted.
sealed class InvitationProof {
  const InvitationProof();
}

class GoogleInvitationProof extends InvitationProof {
  const GoogleInvitationProof(this.idToken);
  final String idToken;
}

class EmailOtpInvitationProof extends InvitationProof {
  const EmailOtpInvitationProof(this.email, this.code);
  final String email;

  /// Deliberately left UNCONSUMED by the 202 login bridge — the accept
  /// call consumes it (mirrors the backend).
  final String code;
}

/// Outcome of a pro LOGIN attempt (three-way, team access R3):
/// signed in · invited (202 bridge: pending invitations + the proof to
/// accept them) · failure (machine `code` + French message).
class ProviderLoginResult {
  const ProviderLoginResult.signedIn(ProviderUser this.provider)
      : invitations = const [],
        proof = null,
        error = null,
        code = null;

  const ProviderLoginResult.invited(
      this.invitations, InvitationProof this.proof)
      : provider = null,
        error = null,
        code = null;

  const ProviderLoginResult.failure(String this.error, {this.code})
      : provider = null,
        invitations = const [],
        proof = null;

  final ProviderUser? provider;
  final List<TeamInvitation> invitations;
  final InvitationProof? proof;
  final String? error;
  final String? code;

  bool get signedIn => provider != null;
  bool get hasInvitations => invitations.isNotEmpty;
}
