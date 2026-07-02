/// Result of handing an email to the provider. [providerMessageId] is the
/// provider's id for the message (correlation/audit).
typedef EmailSendResult = ({bool ok, String? providerMessageId, String? error});

/// The outbound-email seam — the email mirror of `MessagingProvider`.
/// Implementations: [LogEmailProvider] (dev/CI, no network) and
/// `ResendEmailProvider` (prod). Design: docs/design/auth-social-email.md §7.
abstract interface class EmailProvider {
  /// Sends [text] (with an optional [html] alternative) to [to]. Must not
  /// throw — failures come back `ok: false`.
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    String? html,
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
    String? html,
  }) async => (ok: true, providerMessageId: 'log_email_${_seq++}', error: null);
}

/// The French OTP email body (mirrors the SMS template; GSM-agnostic).
String renderOtpEmailText(String code) =>
    'Votre code de vérification MyWeli est $code. Il expire dans 5 minutes.\n\n'
    "Si vous n'êtes pas à l'origine de cette demande, ignorez cet e-mail.";

/// Branded HTML version — deliberately MINIMAL (security email, not
/// marketing): wordmark header, the code front and center, expiry + not-you
/// lines, one-line footer. Table-based + inline styles so every client renders
/// it; the PNG wordmark (email clients don't do SVG) is served by the web
/// (web/public/brand) and degrades to alt text until images load.
String renderOtpEmailHtml(String code) =>
    '''
<!DOCTYPE html>
<html lang="fr">
<body style="margin:0;padding:24px 12px;background-color:#F6F7F9;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background-color:#FFFFFF;border:1px solid #E0E0E0;border-radius:12px;">
        <tr><td style="padding:28px 28px 0;" align="center">
          <img src="https://myweli.com/brand/myweli_lockup_horizontal_black.png" alt="MyWeli" height="34" style="height:34px;width:auto;border:0;">
        </td></tr>
        <tr><td style="padding:20px 28px 0;" align="center">
          <p style="margin:0;font-size:15px;color:#4A4A4A;">Votre code de vérification :</p>
          <p style="margin:12px 0 0;font-size:34px;font-weight:700;letter-spacing:8px;color:#000000;">$code</p>
          <p style="margin:12px 0 0;font-size:13px;color:#8A8A8A;">Il expire dans 5 minutes.</p>
        </td></tr>
        <tr><td style="padding:20px 28px 28px;" align="center">
          <p style="margin:0;font-size:12px;color:#8A8A8A;">Si vous n'êtes pas à l'origine de cette demande, ignorez cet e-mail.</p>
        </td></tr>
      </table>
      <p style="margin:16px 0 0;font-size:12px;color:#8A8A8A;">MyWeli — Réservation beauté &amp; bien-être en Côte d'Ivoire · <a href="https://myweli.com" style="color:#4A4A4A;">myweli.com</a></p>
    </td></tr>
  </table>
</body>
</html>
''';

/// The OTP email subject.
const String otpEmailSubject = 'Votre code MyWeli';
