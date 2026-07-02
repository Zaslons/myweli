/// Result of handing an email to the provider. [providerMessageId] is the
/// provider's id for the message (correlation/audit).
typedef EmailSendResult = ({bool ok, String? providerMessageId, String? error});

/// The outbound-email seam — the email mirror of `MessagingProvider`.
/// Implementations: [LogEmailProvider] (dev/CI, no network) and
/// `ResendEmailProvider` (prod). Design: docs/design/auth-social-email.md §7.
abstract interface class EmailProvider {
  /// Sends [text] to [to]. Must not throw — failures come back `ok: false`.
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
  });
}

/// Dev/CI provider: never touches the network, always "sends". Deliberately
/// **does not log the body** (OTP-safe).
class LogEmailProvider implements EmailProvider {
  var _seq = 0;

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
  }) async => (ok: true, providerMessageId: 'log_email_${_seq++}', error: null);
}

/// The French OTP email body (mirrors the SMS template; GSM-agnostic).
String renderOtpEmailText(String code) =>
    'Votre code de vérification MyWeli est $code. Il expire dans 5 minutes.\n\n'
    "Si vous n'êtes pas à l'origine de cette demande, ignorez cet e-mail.";

/// The OTP email subject.
const String otpEmailSubject = 'Votre code MyWeli';
