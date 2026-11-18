import 'provider_login_result.dart';
import 'provider_user.dart';
import 'team_invitation.dart';

/// Which call answered a sign-up (docs/design/pro-android-signup.md §2.1,
/// §2.5 S7): the sign-in check run first with the same identity, or the
/// register that follows it. The same machine code means different things
/// from each — `invalid_input` from the check is a malformed code, from
/// register the salon's fields.
enum ProSignUpStage { check, register }

/// The outcome of one Android sign-up attempt (§2.1, §5.2).
///
/// - [ProviderSignUpCreated]: the check found no account, and register
///   created it with a draft salon (S2, `201`).
/// - [ProviderSignUpSignedIn]: the check found an account and signed it in;
///   nothing was created (S3, `200`).
/// - [ProviderSignUpInvited]: the check found pending invitations (S4,
///   `202`), with the proof that accepts them.
/// - [ProviderSignUpFailure]: a refusal, its machine [ProviderSignUpFailure.code],
///   the sentence the sign-in would say for it, and the [ProSignUpStage].
sealed class ProviderSignUpResult {
  const ProviderSignUpResult();
}

class ProviderSignUpCreated extends ProviderSignUpResult {
  const ProviderSignUpCreated(this.provider);
  final ProviderUser provider;
}

class ProviderSignUpSignedIn extends ProviderSignUpResult {
  const ProviderSignUpSignedIn(this.provider);
  final ProviderUser provider;
}

class ProviderSignUpInvited extends ProviderSignUpResult {
  const ProviderSignUpInvited(this.invitations, this.proof);
  final List<TeamInvitation> invitations;

  /// Memory only, never persisted or logged (§6.4).
  final InvitationProof proof;
}

/// **`ProAuthProvider` only, never a service:** the account signed in, then
/// the membership refresh found no membership and nothing pending, and ended
/// the session — a former team member (S3b). The provider has already gone
/// back to the sign-in, which shows why.
class ProviderSignUpEnded extends ProviderSignUpResult {
  const ProviderSignUpEnded();
}

class ProviderSignUpFailure extends ProviderSignUpResult {
  const ProviderSignUpFailure(this.message, {this.code, required this.stage});

  /// The sign-in's sentence for [code], else the generic one; empty for a
  /// closed Google sheet (`cancelled`, S14).
  final String message;
  final String? code;
  final ProSignUpStage stage;
}
