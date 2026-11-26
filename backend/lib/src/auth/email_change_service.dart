import '../email/account_email_emails.dart';
import '../email/email_provider.dart';
import '../email/send_budget.dart';
import '../security/identity_limits.dart';
import '../security/rate_limiter.dart';
import 'auth_repository.dart';

/// What a change request did (`POST /me/email/otp/request`, §3.1).
///
/// [devCode] is the new address's code and [currentDevCode] the current
/// address's, both only where the repository echoes codes (dev): nothing
/// outside a test changes an address, so there is no smoke seam here.
/// [currentCodeSent]: decision 265's second code went to the current address.
typedef EmailChangeRequestResult = ({
  bool ok,
  String? error,
  int expiresInSeconds,
  String? devCode,
  String? currentDevCode,
  bool currentCodeSent,
});

EmailChangeRequestResult _requestRefused(String error) => (
  ok: false,
  error: error,
  expiresInSeconds: 0,
  devCode: null,
  currentDevCode: null,
  currentCodeSent: false,
);

/// An account's e-mail change (B16.3, docs/design/account-email-change.md
/// §3.1, §5.2, decisions 261, 262, 265): a code to the new address, and to
/// the current one when it is the account's only way in; then
/// [AuthRepository.changeEmail], which owns the rules and the transaction;
/// then a notice to the address it replaced.
///
/// **A service, though the sign-in routes call the repository directly**
/// (the spec's §5.6 said none was added): the per-account limit needs the
/// [RateLimiter], which only services receive, and the send-and-refund dance
/// is the request route's in `/auth/email/otp/request` — one copy of it there
/// is enough.
class EmailChangeService {
  EmailChangeService(
    this._auth,
    this._email, {
    RateLimiter? limiter,
    int limit = kEmailChangeLimit,
    void Function(String)? log,
  }) : _limiter = limiter,
       _limit = limit,
       _log = log;

  final AuthRepository _auth;
  final EmailProvider _email;
  final RateLimiter? _limiter;
  final int _limit;
  final void Function(String)? _log;

  Future<bool> _underLimit(String userId) =>
      allowUnderLimit(_limiter, emailChangeBucket(userId), _limit, log: _log);

  /// Sends a code to [email] for [userId], and one to its current address
  /// when [AuthRepository.emailIsOnlySignIn]. The same answer whether or not
  /// [email] has an account (T32): « taken » is said only at the verify.
  ///
  /// Errors: `not_found`, `account_suspended`, `email_unchanged` (already its
  /// proven address — its own unproven one is accepted: that is how it gets
  /// proven), `rate_limited`, `otp_resend_limit`.
  Future<EmailChangeRequestResult> request(String userId, String email) async {
    final user = await _auth.userById(userId);
    if (user == null) return _requestRefused('not_found');
    if (user.status == 'banned') return _requestRefused('account_suspended');
    final key = email.trim().toLowerCase();
    if (user.email?.toLowerCase() == key && user.emailVerified) {
      return _requestRefused('email_unchanged');
    }
    if (!await _underLimit(userId)) return _requestRefused('rate_limited');

    final fresh = await _auth.requestEmailOtp(key);
    if (!fresh.ok) return _requestRefused(fresh.error ?? 'otp_resend_limit');
    // COLD: the caller typed this address, as at sign-in.
    await _sendCode(key, fresh.code, EmailClass.cold);

    final current = user.email?.toLowerCase();
    OtpRequestResult? second;
    if (current != null && await _auth.emailIsOnlySignIn(userId)) {
      second = await _auth.requestEmailOtp(current);
      if (!second.ok) {
        return _requestRefused(second.error ?? 'otp_resend_limit');
      }
      // WARM: the account's own proven address.
      await _sendCode(current, second.code, EmailClass.warm);
    }
    return (
      ok: true,
      error: null,
      expiresInSeconds: fresh.expiresInSeconds,
      devCode: fresh.devCode,
      currentDevCode: second?.devCode,
      currentCodeSent: second != null,
    );
  }

  /// The sign-in's delivery, and its refund on a budget that declined to
  /// send (docs/design/backend-email-send-budget.md §9).
  Future<void> _sendCode(String to, String? code, EmailClass cls) async {
    if (code == null) return;
    final sent = await _email.send(
      classification: cls,
      to: to,
      subject: otpEmailSubject,
      text: renderOtpEmailText(code),
      html: renderOtpEmailHtml(code),
    );
    if (sent.error == 'send_budget_exhausted') {
      await _auth.refundEmailOtpResend(to);
    }
  }

  /// Proves [email] (and the current address, decision 265) and makes it
  /// [userId]'s; on success, a notice to the PROVEN address it replaced.
  /// The repository's answers, and `rate_limited`.
  Future<EmailChangeResult> verify(
    String userId,
    String email,
    String code, {
    String? currentCode,
  }) async {
    if (!await _underLimit(userId)) return emailChangeRefused('rate_limited');
    final result = await _auth.changeEmail(
      userId,
      email,
      code,
      currentCode: currentCode,
    );
    final previous = result.previousEmail;
    if (result.ok && previous != null) {
      // Best effort, as every notice: the change is made either way, and
      // `send` does not throw.
      await _email.send(
        classification: EmailClass.warm,
        to: previous,
        subject: accountEmailChangedSubject,
        text: renderAccountEmailChangedText(),
        html: renderAccountEmailChangedHtml(),
      );
    }
    return result;
  }
}
